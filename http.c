/*---------------------------------------------------------------------
 *
 * http.c
 *
 * HTTP transport of rdf_fdw: sends a SPARQL query or update to the
 * endpoint through libcurl, retries what can be retried, and leaves
 * the response body in the scan's state for the caller to parse.
 *
 * Copyright (C) 2022-2026 Jim Jones <jim.jones@uni-muenster.de>
 *
 *---------------------------------------------------------------------
 */
#include "postgres.h"

#include <curl/curl.h>
#include <time.h>

#include "http.h"
#include "rdf_fdw.h"
#include "rdf_utils.h"

#include "lib/stringinfo.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "port.h"
#include "utils/elog.h"
#include "utils/memutils.h"

struct MemoryStruct
{
	char *memory;
	size_t size;
	size_t capacity;	  /* bytes allocated for memory (before PostgreSQL 16) */
	size_t max_size;	  /* 0 = unlimited */
	bool size_exceeded;	  /* max_size was reached, transfer aborted */
	bool buffer_failed;	  /* could not be buffered, transfer aborted */
};

static long GetResponseCode(CURL *curl);
static bool IsRetryableStatus(long response_code);
static long ParseRetryAfter(const char *headers);
static void WaitBeforeRetry(long seconds);

/*
 * CleanupHTTPResources
 * --------------------
 *
 * Releases the libcurl handle and the list of request headers held by a scan.
 * Safe to call more than once, and on a scan that never opened either, which
 * is what lets the same function serve both the ordinary end of a request and
 * the cleanup that follows an error.
 *
 * state: the scan whose HTTP resources are to be released
 */
void CleanupHTTPResources(RDFfdwState *state)
{
	if (state->curl)
	{
		curl_easy_setopt(state->curl, CURLOPT_NOPROGRESS, 1L);
		curl_easy_setopt(state->curl, CURLOPT_VERBOSE, 0L);
		curl_easy_cleanup(state->curl);
		state->curl = NULL;
	}
	if (state->curl_headers)
	{
		curl_slist_free_all(state->curl_headers);
		state->curl_headers = NULL;
	}
}

/*
 * AppendHTTPHeader
 * ----------------
 * Adds one header to the list the next request will carry, keeping the list on
 * the scan's state so that the cleanup above can release it however the scan
 * ends.
 */
static void AppendHTTPHeader(RDFfdwState *state, const char *header)
{
	struct curl_slist *headers;

	/*
	 * libcurl sends a header exactly as given, so a CR or LF in it -- from the
	 * format option or the token of a user mapping -- would start a header
	 * line, or a request, of its own. Every header goes through here.
	 */
	if (ContainsControlCharacters(header))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
				 errmsg("invalid HTTP header for server \"%s\": control characters are not allowed",
						state->server->servername),
				 errhint("Check the options of the SERVER and of the USER MAPPING.")));

	headers = curl_slist_append(state->curl_headers, header);

	if (headers == NULL)
		ereport(ERROR, (errcode(ERRCODE_FDW_OUT_OF_MEMORY),
						errmsg("could not allocate an HTTP request header")));
	state->curl_headers = headers;
}

/*
 * CURLWriteMemoryCallback
 * -----------------------
 * Appends a chunk of a libcurl transfer to the MemoryStruct libcurl was given
 * for it. It serves both CURLOPT_WRITEFUNCTION and CURLOPT_HEADERFUNCTION:
 * what separates the response body from the response headers is the buffer
 * each is handed through CURLOPT_WRITEDATA and CURLOPT_HEADERDATA, not the
 * function, so one implementation covers both and cannot mix them.
 *
 * Both callbacks receive a pointer and a count. libcurl does not promise a
 * terminator after those bytes, so the chunk is copied by its count and the
 * terminator is placed by this function, on its own buffer.
 */
static size_t CURLWriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
	size_t realsize = size * nmemb;
	struct MemoryStruct *mem = (struct MemoryStruct *)userp;
	char *ptr;

	/* DEBUG5, as how many calls a response takes depends on its chunking */
	elog(DEBUG5, "%s called", __func__);

	/*
	 * Nothing may be raised from here: an ereport() would longjmp out of
	 * libcurl, which then never releases the transfer -- its connection,
	 * socket and decoder stay behind for the life of the backend, still
	 * pointing at buffers on the stack of ExecuteSPARQL(). Every failure
	 * aborts the transfer instead, by returning a short count, and is
	 * reported once curl_easy_perform() has returned.
	 */
	if (mem->max_size > 0 && mem->size + realsize > mem->max_size)
	{
		elog(DEBUG1, "%s: response exceeds max_response_size of %zu bytes, aborting transfer",
			 __func__, mem->max_size);
		mem->size_exceeded = true;
		return 0;
	}

	/*
	 * A buffer cannot outgrow MaxAllocSize, which a response can reach even
	 * without max_response_size set, or set beyond it: a few kilobytes of
	 * gzip decode to a gigabyte before they get here.
	 */
	if (realsize >= MaxAllocSize - mem->size)
	{
		mem->buffer_failed = true;
		return 0;
	}

#if PG_VERSION_NUM >= 160000
	/*
	 * repalloc_extended() reports a failure by returning NULL, and grows a
	 * large buffer with realloc(), which usually extends it in place.
	 */
	ptr = repalloc_extended(mem->memory, mem->size + realsize + 1, MCXT_ALLOC_NO_OOM);
	if (ptr == NULL)
	{
		mem->buffer_failed = true;
		return 0;
	}

	mem->memory = ptr;
#else
	/*
	 * Before PostgreSQL 16 repalloc() cannot fail without raising, so a new
	 * buffer is allocated and the old one copied over. Copying the whole
	 * buffer for every chunk would be quadratic, so it grows by doubling;
	 * ExecuteSPARQL() trims what is left over once the transfer is done.
	 */
	if (mem->size + realsize + 1 > mem->capacity)
	{
		size_t newcapacity = Max(mem->capacity, 1024);

		while (newcapacity < mem->size + realsize + 1)
			newcapacity *= 2;
		newcapacity = Min(newcapacity, MaxAllocSize);

		ptr = MemoryContextAllocExtended(GetMemoryChunkContext(mem->memory),
										 newcapacity, MCXT_ALLOC_NO_OOM);
		if (ptr == NULL)
		{
			mem->buffer_failed = true;
			return 0;
		}

		memcpy(ptr, mem->memory, mem->size + 1);
		pfree(mem->memory);
		mem->memory = ptr;
		mem->capacity = newcapacity;
	}
#endif

	memcpy(&(mem->memory[mem->size]), contents, realsize);
	mem->size += realsize;
	mem->memory[mem->size] = 0;

	/*
	 * DEBUG5, with libcurl's own trace: how many bytes arrive in a call is
	 * decided by how the body is chunked on the way, not by what the body
	 * says, so the same response logs different sizes from one run to the
	 * next. The size that can be compared is the total, which is reported
	 * once the transfer is done.
	 */
	elog(DEBUG5, "%s exit: returning '%lu' (realsize)", __func__, realsize);
	return realsize;
}

/*
 * IsSensitiveHeader
 * -----------------
 * Returns the field-name of a sensitive HTTP header if `line` begins with
 * one, or NULL otherwise.  Comparison is case-insensitive (RFC 9110 §5.1).
 */
static const char *
IsSensitiveHeader(const char *line)
{
	static const struct
	{
		const char *name;
		size_t      len;
	} sensitive_headers[] = {
		{ "Authorization:",       sizeof("Authorization:")       - 1 },
		{ "Proxy-Authorization:", sizeof("Proxy-Authorization:") - 1 },
		/* a session cookie grants what the credentials that obtained it do */
		{ "Set-Cookie:",          sizeof("Set-Cookie:")          - 1 },
		{ NULL, 0 }
	};

	for (int i = 0; sensitive_headers[i].name != NULL; i++)
	{
		if (strncasecmp(line, sensitive_headers[i].name,
						sensitive_headers[i].len) == 0)
			return sensitive_headers[i].name;
	}

	return NULL;
}

/*
 * CURLDebugCallback
 * -----------------
 * Custom libcurl debug callback. Routes all verbose output through
 * PostgreSQL's elog() at DEBUG3 level rather than writing directly to
 * stderr, and redacts Authorization headers so credentials are never
 * written to server logs.
 *
 * handle  : the curl handle (unused)
 * type    : category of the debug data
 * data    : pointer to the debug data (NOT null-terminated)
 * size    : number of bytes in data
 * userptr : user-supplied pointer (unused)
 */
static int
CURLDebugCallback(CURL *handle, curl_infotype type, char *data, size_t size, void *userptr)
{
	const char    *prefix;
	StringInfoData buf;

	switch (type)
	{
		case CURLINFO_TEXT:       prefix = "* "; break;
		case CURLINFO_HEADER_IN:  prefix = "< "; break;
		case CURLINFO_HEADER_OUT: prefix = "> "; break;
		default:
			return 0;	/* skip raw data blobs (bodies, SSL frames) */
	}

	/*
	 * curl's data pointer is NOT null-terminated, so copy it into a palloc'd
	 * buffer before using any string functions on it.
	 */
	initStringInfo(&buf);
	appendBinaryStringInfo(&buf, data, (int) size);

	if (type == CURLINFO_HEADER_OUT)
	{
		/*
		 * CURLINFO_HEADER_OUT delivers the entire outgoing request header
		 * block (request line + all headers) as one multi-line chunk per
		 * invocation.  Split it line-by-line so each sensitive header can be
		 * redacted individually.
		 */
		char *pos = buf.data;

		while (*pos != '\0')
		{
			char       *eol   = pos + strcspn(pos, "\r\n");
			char        saved = *eol;
			const char *match;

			*eol = '\0';	/* temporarily terminate the line */

			if (*pos != '\0')	/* skip blank lines */
			{
				match = IsSensitiveHeader(pos);
				if (match)
					elog(DEBUG5, "[curl] > %s [REDACTED]", match);
				else
					elog(DEBUG5, "[curl] > %s", pos);
			}

			*eol = saved;
			pos  = eol;
			while (*pos == '\r' || *pos == '\n')
				pos++;
		}
	}
	else
	{
		const char *match;

		/* Strip trailing CRLF for cleaner log output. */
		while (buf.len > 0 &&
			   (buf.data[buf.len - 1] == '\n' || buf.data[buf.len - 1] == '\r'))
			buf.data[--buf.len] = '\0';

		/*
		 * Redact sensitive response headers.  Informational text lines
		 * (CURLINFO_TEXT) are logged as-is — they never contain raw
		 * credential values.
		 */
		match = (type == CURLINFO_HEADER_IN) ? IsSensitiveHeader(buf.data) : NULL;
		if (match)
			elog(DEBUG5, "[curl] %s%s [REDACTED]", prefix, match);
		else
			elog(DEBUG5, "[curl] %s%s", prefix, buf.data);
	}

	pfree(buf.data);
	return 0;
}

/*
 * CURLProgressCallback
 * --------------------
 * Progress callback function for cURL requests. This allows us to
 * cancel the request as soon as an interrupt is pending.
 *
 * The interrupt itself is serviced after curl_easy_perform() returns: an
 * ereport() from here would longjmp out of libcurl, which then refuses to
 * release the handle's connections.
 *
 * dltotal: Total bytes to download
 * dlnow: Bytes downloaded so far
 * ultotal: Total bytes to upload
 * ulnow: Bytes uploaded so far
 */
static int CURLProgressCallback(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow)
{
	/* a non-zero value aborts the transfer */
	return QueryCancelPending || ProcDiePending;
}

/*
 * GetResponseCode
 * ---------------
 * Returns the HTTP status of the last request, even if libcurl failed. For
 * an HTTPS endpoint behind a proxy, a proxy refusing the CONNECT tunnel with
 * a client error (e.g. 407) leaves no response of the endpoint, so the
 * proxy's answer is returned instead: retrying would not change it. Other
 * answers of the proxy, e.g. 503 for a host it cannot reach, still count as
 * a network error.
 */
static long GetResponseCode(CURL *curl)
{
	long response_code = 0;
	long connect_code = 0;

	curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
	if (response_code == 0)
	{
		curl_easy_getinfo(curl, CURLINFO_HTTP_CONNECTCODE, &connect_code);
		if (connect_code >= 400 && connect_code < 500)
			response_code = connect_code;
	}

	return response_code;
}

/*
 * IsRetryableStatus
 * -----------------
 * Whether an HTTP answer asks to come back later: 429 Too Many Requests,
 * 503 Service Unavailable, and 502 Bad Gateway, which a proxy answers while
 * the endpoint behind it restarts. 504 is not retried, as a query that ran
 * into a gateway's time limit would most likely run into it again.
 */
static bool IsRetryableStatus(long response_code)
{
	return response_code == 429 || response_code == 502 || response_code == 503;
}

/*
 * ParseRetryAfter
 * ---------------
 * Returns the delay in seconds that the Retry-After header asks for, or -1
 * if there is none. Both forms of RFC 9110 section 10.2.3 are accepted,
 * delta-seconds and an HTTP-date. The header block holds the headers of every
 * redirect hop, so the last occurrence wins.
 */
static long ParseRetryAfter(const char *headers)
{
	static const char field[] = "retry-after:";
	const char *line;
	long result = -1;

	if (!headers)
		return -1;

	for (line = headers; *line != '\0';)
	{
		const char *eol = strpbrk(line, "\r\n");
		size_t len = eol ? (size_t)(eol - line) : strlen(line);

		if (len > sizeof(field) - 1 &&
			pg_strncasecmp(line, field, sizeof(field) - 1) == 0)
		{
			const char *v = line + sizeof(field) - 1;
			char value[128];
			size_t vlen;

			/* skip the optional whitespace before the value */
			while (v < line + len && (*v == ' ' || *v == '\t'))
				v++;

			vlen = (size_t)(line + len - v);

			if (vlen > 0 && vlen < sizeof(value))
			{
				char *tail;
				long secs;

				memcpy(value, v, vlen);
				value[vlen] = '\0';

				/* delta-seconds */
				secs = strtol(value, &tail, 10);

				if (tail != value && *tail == '\0' && secs >= 0)
					result = secs;
				else
				{
					/* HTTP-date */
					time_t when = curl_getdate(value, NULL);

					if (when != (time_t)-1)
					{
						double diff = difftime(when, time(NULL));

						result = diff > 0 ? (long)diff : 0;
					}
				}
			}
		}

		if (!eol)
			break;

		line = eol + strspn(eol, "\r\n");
	}

	return result;
}

/*
 * WaitBeforeRetry
 * ---------------
 * Waits the given number of seconds before a request is retried, in steps of
 * one second, so that a cancel or a statement_timeout ends the wait: the
 * signal cuts the current step short, and the next check raises the error.
 */
static void WaitBeforeRetry(long seconds)
{
	for (long i = 0; i < seconds; i++)
	{
		CHECK_FOR_INTERRUPTS();
		pg_usleep(1000000L);
	}
	CHECK_FOR_INTERRUPTS();
}

/*
 * ExecuteSPARQL
 * -------------
 * Executes the SPARQL query in the endpoint set in the CREATE FOREIGN TABLE
 * and CREATE SERVER statements. The result set is loaded into 'state'.
 *
 * state: SPARQL, SERVER and FOREIGN TABLE info
 *
 * returns REQUEST_SUCCESS or REQUEST_FAIL
 */
int ExecuteSPARQL(RDFfdwState *state)
{
	CURLcode res;
	char *sparql;
	StringInfoData url_buffer;
	StringInfoData user_agent;
	StringInfoData accept_header;
	char errbuf[CURL_ERROR_SIZE];
	struct MemoryStruct chunk;
	struct MemoryStruct chunk_header;
	long response_code;

	chunk.memory = palloc0(1);
	chunk.size = 0; /* no data at this point */
	chunk.capacity = 1;
	chunk.max_size = (size_t) state->max_response_size;
	chunk.size_exceeded = false;
	chunk.buffer_failed = false;
	chunk_header.memory = palloc0(1);
	chunk_header.size = 0; /* no data at this point */
	chunk_header.capacity = 1;
	chunk_header.max_size = 0; /* no limit on headers */
	chunk_header.size_exceeded = false;
	chunk_header.buffer_failed = false;

	elog(DEBUG1, "%s called for %s operation", __func__,
		 (state->sparql_query_type == SPARQL_INSERT) ? "INSERT" : (state->sparql_query_type == SPARQL_DELETE) ? "DELETE"
															  : (state->sparql_query_type == SPARQL_UPDATE)	  ? "UPDATE"
																											  : "SELECT/DESCRIBE");

	/*
	 * The SPARQL protocol carries queries and updates in UTF-8, whatever the
	 * encoding of the database they were built in. Converted before libcurl
	 * is set up, as the conversion raises an error for a character it cannot
	 * convert.
	 */
	sparql = pg_server_to_any(state->sparql, strlen(state->sparql), PG_UTF8);

	RegisterRDFResources(state);
	state->curl = curl_easy_init();

	if (!state->curl)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_OUT_OF_MEMORY),
				 errmsg("could not initialize libcurl for server \"%s\"", state->server->servername)));

	initStringInfo(&accept_header);
	appendStringInfo(&accept_header, "Accept: %s", state->format);

	if (state->log_sparql)
		elog(INFO, "SPARQL query sent to '%s':\n%s\n", state->server->servername, state->sparql);

	/* For SPARQL UPDATE operations (INSERT, DELETE, UPDATE), use different approach */
	if (state->sparql_query_type == SPARQL_INSERT ||
		state->sparql_query_type == SPARQL_DELETE ||
		state->sparql_query_type == SPARQL_UPDATE)
	{
		/* SPARQL UPDATE: send the update query directly in POST body with application/sparql-update */
		elog(DEBUG1, "%s: using SPARQL UPDATE protocol", __func__);

		/* No need to build URL parameters for UPDATE */
		initStringInfo(&url_buffer);
	}
	else
	{
		/* SPARQL SELECT/DESCRIBE: use URL-encoded form parameters */
		char *escaped_url = curl_easy_escape(state->curl, sparql, 0);

		if (!escaped_url)
		{
			CleanupRDFResources(state);
			ereport(ERROR,
					(errcode(ERRCODE_FDW_OUT_OF_MEMORY),
					 errmsg("could not URL encode the SPARQL query for server \"%s\"", state->server->servername)));
		}

		initStringInfo(&url_buffer);
		appendStringInfo(&url_buffer, "%s=%s", state->query_param, escaped_url);

		if (state->custom_params)
			appendStringInfo(&url_buffer, "&%s", state->custom_params);

		curl_free(escaped_url);

		elog(DEBUG2, "  %s: url built > %s?%s", __func__, state->endpoint, url_buffer.data);
	}

	if (state->curl)
	{
		errbuf[0] = 0;

		curl_easy_setopt(state->curl, CURLOPT_URL, state->endpoint);

		/* CURLOPT_PROTOCOLS was deprecated in libcurl 7.85 and its enum flags removed
		 * in 8.0; use the string-based CURLOPT_PROTOCOLS_STR on newer versions.
		 *
		 * The redirect counterpart has to be restricted separately: it does not
		 * inherit from the option above, and libcurl allows FTP and FTPS on
		 * redirects by default. */
#if ((LIBCURL_VERSION_MAJOR == 7 && LIBCURL_VERSION_MINOR < 85) || LIBCURL_VERSION_MAJOR < 7)
		curl_easy_setopt(state->curl, CURLOPT_PROTOCOLS, CURLPROTO_HTTP | CURLPROTO_HTTPS);
		curl_easy_setopt(state->curl, CURLOPT_REDIR_PROTOCOLS, CURLPROTO_HTTP | CURLPROTO_HTTPS);
#else
		curl_easy_setopt(state->curl, CURLOPT_PROTOCOLS_STR, "http,https");
		curl_easy_setopt(state->curl, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
#endif

		curl_easy_setopt(state->curl, CURLOPT_ERRORBUFFER, errbuf);

		curl_easy_setopt(state->curl, CURLOPT_CONNECTTIMEOUT, state->connect_timeout);
		curl_easy_setopt(state->curl, CURLOPT_TIMEOUT, state->request_timeout);

		/*
		 * Without an asynchronous resolver, libcurl times out name lookups
		 * with SIGALRM, which PostgreSQL uses for its own timeouts.
		 */
		curl_easy_setopt(state->curl, CURLOPT_NOSIGNAL, 1L);

		/*
		 * A name lookup cannot be interrupted, so after a timeout or an error
		 * libcurl waits for the resolver thread to give up, which can take
		 * much longer than connect_timeout. Leave the thread behind instead;
		 * it releases its resources itself once the lookup returns.
		 */
#if LIBCURL_VERSION_NUM >= 0x075700
		curl_easy_setopt(state->curl, CURLOPT_QUICK_EXIT, 1L);
#endif
		elog(DEBUG2, "  %s: connect_timeout > %ld", __func__, state->connect_timeout);
		elog(DEBUG2, "  %s: request_timeout > %ld", __func__, state->request_timeout);
		elog(DEBUG2, "  %s: max retry > %ld", __func__, state->max_retries);

		if (state->proxy)
		{
			elog(DEBUG2, "  %s: proxy URL > '%s'", __func__, state->proxy);

			curl_easy_setopt(state->curl, CURLOPT_PROXY, state->proxy);

			if (strcmp(state->proxy_type, RDF_SERVER_OPTION_HTTP_PROXY) == 0)
			{
				elog(DEBUG2, "  %s: proxy protocol > 'HTTP'", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYTYPE, (long)CURLPROXY_HTTP);
			}
			else if (strcmp(state->proxy_type, RDF_SERVER_OPTION_HTTPS_PROXY) == 0)
			{
				elog(DEBUG2, "  %s: proxy protocol > 'HTTPS'", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYTYPE, (long)CURLPROXY_HTTPS);
			}

			if (state->proxy_user)
			{
				elog(DEBUG2, "  %s: entering proxy user ('%s').", __func__, state->proxy_user);
				curl_easy_setopt(state->curl, CURLOPT_PROXYUSERNAME, state->proxy_user);
			}

			if (state->proxy_user_password)
			{
				elog(DEBUG2, "  %s: entering proxy user's password.", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYPASSWORD, state->proxy_user_password);
			}
		}

		if (state->request_max_redirect > 0)
		{
			elog(DEBUG2, "  %s: following redirects, maxredirs: %ld", __func__, state->request_max_redirect);
			curl_easy_setopt(state->curl, CURLOPT_FOLLOWLOCATION, 1L);

			/* Never forward credentials to a redirected host */
			curl_easy_setopt(state->curl, CURLOPT_UNRESTRICTED_AUTH, 0L);

			/*
			 * Set the limit explicitly, so that it never depends on the
			 * default of the libcurl release this was linked against.
			 */
			curl_easy_setopt(state->curl, CURLOPT_MAXREDIRS, state->request_max_redirect);
		}
		else
		{
			elog(DEBUG2, "  %s: redirects disabled", __func__);
			curl_easy_setopt(state->curl, CURLOPT_FOLLOWLOCATION, 0L);
		}

		/* Set POST data based on query type */
		if (state->sparql_query_type == SPARQL_INSERT ||
			state->sparql_query_type == SPARQL_DELETE ||
			state->sparql_query_type == SPARQL_UPDATE)
		{
			/* For SPARQL UPDATE: send raw SPARQL update in POST body */
			elog(DEBUG1, "%s: setting SPARQL UPDATE body: %s", __func__, state->sparql);
			curl_easy_setopt(state->curl, CURLOPT_POSTFIELDS, sparql);
			curl_easy_setopt(state->curl, CURLOPT_POSTFIELDSIZE, (long)strlen(sparql));
		}
		else
		{
			/* For SPARQL SELECT/DESCRIBE: send URL-encoded parameters */
			curl_easy_setopt(state->curl, CURLOPT_POSTFIELDS, url_buffer.data);
		}

		curl_easy_setopt(state->curl, CURLOPT_HEADERFUNCTION, CURLWriteMemoryCallback);
		curl_easy_setopt(state->curl, CURLOPT_HEADERDATA, (void *)&chunk_header);

		/* For SPARQL UPDATE operations, collect the response body so that
		 * error details (e.g. auth failure messages) can be surfaced in the
		 * PostgreSQL error.  max_size is reset to 0 (unlimited) to avoid a
		 * false "exceeds max_response_size" error when the endpoint returns
		 * a large body on a successful update (e.g. QLever JSON). */
		if (state->sparql_query_type == SPARQL_INSERT ||
			state->sparql_query_type == SPARQL_DELETE ||
			state->sparql_query_type == SPARQL_UPDATE)
			chunk.max_size = 0;

		curl_easy_setopt(state->curl, CURLOPT_WRITEFUNCTION, CURLWriteMemoryCallback);
		curl_easy_setopt(state->curl, CURLOPT_WRITEDATA, (void *)&chunk);

		/*
		 * Offer every encoding this libcurl can decode: SPARQL XML compresses
		 * very well. libcurl decodes before the write callback, so
		 * max_response_size still limits the decoded size.
		 */
		curl_easy_setopt(state->curl, CURLOPT_ACCEPT_ENCODING, "");

		/* Don't use CURLOPT_FAILONERROR so we can capture error response bodies */
		curl_easy_setopt(state->curl, CURLOPT_FAILONERROR, 0L);

		/*
		 * Enable libcurl verbose output, but route it exclusively through
		 * CURLDebugCallback instead of stderr. The callback emits at DEBUG5
		 * (gated by log_min_messages) and redacts Authorization headers so
		 * credentials are never written to server logs.
		 *
		 * DEBUG5 rather than DEBUG3 because this is libcurl's trace, not the
		 * extension's, and none of it repeats: it carries the response Date,
		 * whatever session cookie the server issues, the address the host
		 * resolved to and the server's own request counter. Sharing a level
		 * with the extension's tracing made DEBUG3 unusable for anything that
		 * compares two runs, which is what sql/debug.sql does.
		 */
		curl_easy_setopt(state->curl, CURLOPT_VERBOSE, 1L);
		curl_easy_setopt(state->curl, CURLOPT_DEBUGFUNCTION, CURLDebugCallback);
		curl_easy_setopt(state->curl, CURLOPT_DEBUGDATA, NULL);

		/* Set the progress callback function */
		curl_easy_setopt(state->curl, CURLOPT_XFERINFOFUNCTION, CURLProgressCallback);

		/* Optional: Pass user data to the callback (NULL in this case) */
		curl_easy_setopt(state->curl, CURLOPT_XFERINFODATA, NULL);

		/* Enable progress callback */
		curl_easy_setopt(state->curl, CURLOPT_NOPROGRESS, 0L);

		/*
		 * The User-Agent names the wrapper and where to find it -- the form
		 * Wikimedia's User-Agent policy asks of a client, for instance -- and
		 * nothing else: no version of PostgreSQL, libxml2, libcurl or the TLS
		 * library, which would tell every endpoint and proxy on the way which
		 * known vulnerabilities to try. rdf_fdw_settings reports those
		 * locally.
		 */
		initStringInfo(&user_agent);
		appendStringInfo(&user_agent, "rdf_fdw/%s (+%s)", FDW_VERSION, FDW_URL);
		curl_easy_setopt(state->curl, CURLOPT_USERAGENT, user_agent.data);

		/* Set headers based on query type */
		if (state->sparql_query_type == SPARQL_INSERT ||
			state->sparql_query_type == SPARQL_DELETE ||
			state->sparql_query_type == SPARQL_UPDATE)
		{
			/* For SPARQL UPDATE: use application/sparql-update content type */
			AppendHTTPHeader(state, "Content-Type: application/sparql-update");
			elog(DEBUG1, "%s: setting Content-Type: application/sparql-update", __func__);
		}
		else
		{
			/* For SPARQL SELECT/DESCRIBE: use standard accept header */
			AppendHTTPHeader(state, accept_header.data);
		}

		/*
		 * Bearer token authentication as defined by RFC 6750
		 * (https://datatracker.ietf.org/doc/html/rfc6750).
		 * This is the standard mechanism for OAuth 2.0 token-based
		 * authentication.
		 */
		if (state->token)
		{
			StringInfoData auth_header;
			initStringInfo(&auth_header);
			appendStringInfo(&auth_header, "Authorization: Bearer %s", state->token);
			AppendHTTPHeader(state, auth_header.data);
			elog(DEBUG2, "%s: setting Authorization: Bearer [REDACTED]", __func__);
		}

		curl_easy_setopt(state->curl, CURLOPT_HTTPHEADER, state->curl_headers);

		if (state->user && state->password)
		{
			curl_easy_setopt(state->curl, CURLOPT_HTTPAUTH, CURLAUTH_BASIC);
			curl_easy_setopt(state->curl, CURLOPT_USERNAME, state->user);
			curl_easy_setopt(state->curl, CURLOPT_PASSWORD, state->password);
		}
		else if (state->user && !state->password)
		{
			curl_easy_setopt(state->curl, CURLOPT_HTTPAUTH, CURLAUTH_BASIC);
			curl_easy_setopt(state->curl, CURLOPT_USERNAME, state->user);
		}

		elog(DEBUG2, "  %s: performing cURL request ... ", __func__);

		res = curl_easy_perform(state->curl);
		CHECK_FOR_INTERRUPTS();

		/* Always get response code - even if cURL failed */
		response_code = GetResponseCode(state->curl);

		elog(DEBUG2, "  %s: cURL result=%d, HTTP status=%ld, response size=%zu",
			 __func__, res, response_code, chunk.size);

		/*
		 * Retry on network errors (no response received) and on answers that
		 * ask to come back later, but not on other HTTP errors, which an
		 * identical request would get again - and never when the transfer
		 * was aborted on purpose, as every attempt would hit the same limit.
		 * The wait between attempts doubles, so that an endpoint that is down
		 * or throttling is not hammered with requests, unless the endpoint
		 * says how long to wait in Retry-After.
		 *
		 * SPARQL UPDATE requests are retried as well: they only consist of
		 * INSERT DATA and DELETE DATA without blank nodes, which leave the
		 * same graph if the endpoint happens to apply them twice.
		 */
		for (long i = 0; i < state->max_retries && !chunk.size_exceeded &&
			 !chunk.buffer_failed && !chunk_header.buffer_failed &&
			 ((res != CURLE_OK && response_code == 0) || IsRetryableStatus(response_code));
			 i++)
		{
			long wait;

			if (response_code != 0)
			{
				wait = ParseRetryAfter(chunk_header.memory);
				if (wait < 0)
					wait = RDF_RETRY_THROTTLED_WAIT << Min(i, 16);
				wait = Min(wait, RDF_RETRY_MAX_WAIT);
				ereport(WARNING,
						(errmsg_plural("server \"%s\" answered HTTP %ld, retrying in %ld second (%ld/%ld)",
									   "server \"%s\" answered HTTP %ld, retrying in %ld seconds (%ld/%ld)",
									   wait, state->server->servername, response_code, wait,
									   i + 1, state->max_retries)));
			}
			else
			{
				wait = Min(RDF_RETRY_NETWORK_WAIT << Min(i, 16), RDF_RETRY_MAX_WAIT);
				elog(WARNING, "%s: request to '%s' failed (%ld)", __func__, state->server->servername, i + 1);
			}

			WaitBeforeRetry(wait);

			/*
			 * Discard whatever the failed attempt left behind *before*
			 * retrying: a connection that drops mid-transfer may well
			 * have written part of a response body already, and that
			 * would otherwise be concatenated with the body of the retry.
			 */
			chunk.size = 0;
			chunk.memory[0] = '\0';
			chunk_header.size = 0;
			chunk_header.memory[0] = '\0';

			res = curl_easy_perform(state->curl);
			CHECK_FOR_INTERRUPTS();
			response_code = GetResponseCode(state->curl);
		}

		/*
		 * The write callback aborts the transfer when the response outgrows
		 * max_response_size. Report it here, where the libcurl handle can
		 * still be released, and before any HTTP status is considered: the
		 * response body is incomplete either way, so the size limit is what
		 * the user needs to hear about.
		 */
		if (chunk.size_exceeded)
		{
			CleanupRDFResources(state);

			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("SPARQL response exceeds max_response_size limit of %zu bytes", chunk.max_size),
					 errhint("Increase max_response_size in CREATE SERVER or refine your SPARQL query to return fewer results.")));
		}

		if (chunk.buffer_failed || chunk_header.buffer_failed)
		{
			CleanupRDFResources(state);

			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("SPARQL response from server \"%s\" is too large to be buffered",
							state->server->servername),
					 errdetail("A decoded response may not exceed %zu bytes, and must fit in the memory available.",
							   (size_t) MaxAllocSize - 1),
					 errhint("Set max_response_size in CREATE SERVER or refine your SPARQL query to return fewer results.")));
		}

		/* Check for HTTP errors first (with FAILONERROR=false, we get the response body) */
		if (response_code >= 400)
		{
			/* HTTP error - response body should contain error details */
			elog(DEBUG1, "%s: HTTP error %ld, response size=%zu, header size=%zu",
				 __func__, response_code, chunk.size, chunk_header.size);

			{
				StringInfoData display_body;
				bool has_body = (chunk.size > 0 && chunk.memory);

				initStringInfo(&display_body);

				if (has_body)
				{
					/*
					 * Truncate the error body before logging or including in
					 * error messages.  Endpoints may return large HTML pages on
					 * errors (e.g. from misconfigured proxies), which would
					 * flood server logs.  The cut falls on a character
					 * boundary of the UTF-8 the body is most likely in, so the
					 * message does not end in half a character.
					 */
					if (chunk.size > RDF_FDW_MAX_ERROR_BODY)
					{
						appendBinaryStringInfo(&display_body, chunk.memory,
											   pg_encoding_mbcliplen(PG_UTF8, chunk.memory,
																	 (int) chunk.size,
																	 RDF_FDW_MAX_ERROR_BODY));
						appendStringInfoString(&display_body, "... (truncated)");
					}
					else
					{
						appendStringInfoString(&display_body, chunk.memory);
					}
					elog(DEBUG1, "%s: error response body: %s", __func__, display_body.data);
				}
				else
				{
					elog(DEBUG1, "%s: no response body available for HTTP error %ld", __func__, response_code);
				}

				CleanupRDFResources(state);

				if (response_code == 400)
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("bad request on server \"%s\" (HTTP 400)", state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0,
							 errhint("Check the SPARQL query syntax.")));
				else if (response_code == 401)
					ereport(ERROR,
							(errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION),
							 errmsg("authentication failed on server \"%s\" (HTTP 401)", state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0,
							 errhint("Check the credentials in the USER MAPPING for PostgreSQL user \"%s\".", GetUserNameFromId(state->userid, false))));
				else if (response_code == 403)
					ereport(ERROR,
							(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
							 errmsg("access denied on server \"%s\" (HTTP 403)", state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0,
							 errhint("The server understood the request but the authenticated user lacks permission to access the endpoint.")));
				else if (response_code == 404)
					ereport(ERROR,
							(errcode(ERRCODE_FDW_UNABLE_TO_ESTABLISH_CONNECTION),
							 errmsg("endpoint not found on server \"%s\" (HTTP 404)", state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0,
							 errhint("Check the endpoint URL: \"%s\".", state->endpoint)));
				else if (response_code == 406)
					ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							errmsg("unacceptable response format on server \"%s\" (HTTP 406)", state->server->servername),
							has_body ? errdetail("%s", display_body.data) : 0,
							errhint("The endpoint does not support the requested format. "
									"Check the 'format' option in CREATE SERVER.")));
				else if (response_code == 407)
					ereport(ERROR,
							(errcode(ERRCODE_FDW_UNABLE_TO_ESTABLISH_CONNECTION),
							 errmsg("proxy authentication required on server \"%s\" (HTTP 407)", state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0,
							 errhint("The endpoint requires proxy authentication. Check the proxy settings.")));
				else if (response_code == 429)
					ereport(ERROR,
							(errcode(ERRCODE_FDW_ERROR),
							 errmsg("too many requests on server \"%s\" (HTTP 429)", state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0,
							 errhint("The endpoint is rate-limiting requests. Consider reducing query frequency or adding a delay between requests.")));
				else if (response_code == 500)
					ereport(ERROR,
							(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
							 errmsg("internal error on server \"%s\" (HTTP 500)", state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0));
				else if (response_code == 503)
					ereport(ERROR,
							(errcode(ERRCODE_FDW_UNABLE_TO_ESTABLISH_CONNECTION),
							 errmsg("service unavailable on server \"%s\" (HTTP 503)", state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0,
							 errhint("The endpoint is temporarily unavailable. Try again later.")));
				else
					ereport(ERROR,
							(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
							 errmsg("HTTP %ld error on server \"%s\"", response_code, state->server->servername),
							 has_body ? errdetail("%s", display_body.data) : 0));
			}
		}
		else if (res != CURLE_OK)
		{
			/* cURL/network error */
			size_t len = strlen(errbuf);
			const char *curl_err = curl_easy_strerror(res);

			CleanupRDFResources(state);

			if (len)
			{
				ereport(ERROR,
						(errcode(ERRCODE_FDW_UNABLE_TO_ESTABLISH_CONNECTION),
						 errmsg("unable to connect to '%s'", state->server->servername),
						 errdetail("%s (curl error code %u).", curl_err, res)));
			}
			else
			{
				ereport(ERROR,
						(errcode(ERRCODE_FDW_UNABLE_TO_ESTABLISH_CONNECTION),
						 errmsg("%s => (%u) '%s'\n", __func__, res, curl_err)));
			}
		}
		else if (response_code < 200 || response_code >= 300)
		{
			CleanupRDFResources(state);
			ereport(ERROR,
					(errcode(ERRCODE_FDW_ERROR),
					 errmsg("unexpected HTTP status %ld from server \"%s\"",
							response_code, state->server->servername),
					 errhint("Only HTTP 2xx responses indicate success. Check the endpoint and redirect settings.")));
		}
		else
		{
			/* Success - HTTP 2xx */

#if PG_VERSION_NUM < 160000
			/*
			 * The write callback grows the buffer by doubling (see
			 * CURLWriteMemoryCallback), which can leave nearly as much unused
			 * as the response itself. Give it back before anything else is
			 * allocated: a large buffer is shrunk by realloc(), normally in
			 * place (a small one is left as it is), and raising here, outside
			 * libcurl, is safe.
			 */
			if (chunk.capacity > chunk.size + 1)
			{
				chunk.memory = repalloc(chunk.memory, chunk.size + 1);
				chunk.capacity = chunk.size + 1;
			}
#endif

			state->sparql_resultset = pstrdup(chunk.memory);

			elog(DEBUG4, "%s: xml document \n\n%s", __func__, chunk.memory);
			elog(DEBUG2, "%s: http response code = %ld", __func__, response_code);
			elog(DEBUG2, "%s: http response size = %zu", __func__, chunk.size);
		}
	}

	CleanupHTTPResources(state);
	pfree(chunk.memory);
	pfree(chunk_header.memory);

	/*
	 * We thrown an error in case the SPARQL endpoint returns an empty XML doc
	 */
	if (!state->sparql_resultset)
	{
		elog(DEBUG1, "%s exit: REQUEST_FAIL", __func__);
		return REQUEST_FAIL;
	}

	elog(DEBUG1, "%s exit: REQUEST_SUCCESS", __func__);
	return REQUEST_SUCCESS;
}
