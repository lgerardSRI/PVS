/*
 DOCUMENTATION INFORMATION				          module: PLOT
 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
 system	   : Apollo DN3000, HP 9000/S500
 file	   : run_child.h
 unit-title: 
 ref.	   : 
 author(s) : Copyright (c) 1991-1994 G.L.J.M. Janssen
 date	   :  7-JUN-1994
 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
*/

#ifndef _RUN_CHILD_H
#define _RUN_CHILD_H

/* ------------------------------------------------------------------------ */
/* INCLUDES                                                                 */
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */
/* DEFINES                                                                  */
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */
/* TYPE DEFINITIONS                                                         */
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */
/* VARIABLES                                                                */
/* ------------------------------------------------------------------------ */
static char SccsId_RUN_CHILD_H[] = "%Z%%Y%/%M% %I% %G%";

/* ------------------------------------------------------------------------ */
/* FUNCTION PROTOTYPES                                                      */
/* ------------------------------------------------------------------------ */

extern int run_child (const char *child_name,
		      const char *options,
		      int Monitor,
		      const char *mon_file_name_prefix,
		      FILE **std_in, FILE **std_out);

#endif /* _RUN_CHILD_H */
