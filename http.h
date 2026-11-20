/*---------------------------------------------------------------------
 *
 * http.h
 *
 * HTTP transport of rdf_fdw (see http.c).
 *
 * Copyright (C) 2022-2026 Jim Jones <jim.jones@uni-muenster.de>
 *
 *---------------------------------------------------------------------
 */

#ifndef RDF_FDW_HTTP_H
#define RDF_FDW_HTTP_H

#include "rdf_fdw.h"

extern int ExecuteSPARQL(RDFfdwState *state);
extern void CleanupHTTPResources(RDFfdwState *state);

#endif /* RDF_FDW_HTTP_H */
