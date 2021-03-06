/*-
 * Copyright (c) 1995 Alex Tatmanjants <alex@elvisti.kiev.ua>
 *		at Electronni Visti IA, Kiev, Ukraine.
 *			All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * Copyright (c) 2011-2012 Dmitry Moskalchuk <dm@crystax.net>.
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without modification, are
 * permitted provided that the following conditions are met:
 * 
 *    1. Redistributions of source code must retain the above copyright notice, this list of
 *       conditions and the following disclaimer.
 * 
 *    2. Redistributions in binary form must reproduce the above copyright notice, this list
 *       of conditions and the following disclaimer in the documentation and/or other materials
 *       provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY Dmitry Moskalchuk ''AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 * FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Dmitry Moskalchuk OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * The views and conclusions contained in the software and documentation are those of the
 * authors and should not be interpreted as representing official policies, either expressed
 * or implied, of Dmitry Moskalchuk.
 */

#include <sys/cdefs.h>
__FBSDID("$FreeBSD$");

#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <locale.h>

#include "collate.h"
#include "setlocale.h"
#include "ldpart.h"

#ifdef __ANDROID__
#include "crystax/private.h"
#endif

int __collate_load_error = 1;
int __collate_substitute_nontrivial;

u_char __collate_substitute_table[UCHAR_MAX + 1][STR_LEN];
struct __collate_st_char_pri __collate_char_pri_table[UCHAR_MAX + 1];
struct __collate_st_chain_pri *__collate_chain_pri_table;

void __collate_err(int ex, const char *f) __dead2;

int
__collate_load_tables(const char *encoding)
{
	__crystax_locale_data_t *ld;
    int fpos;
	int i, saverr, chains;
	uint32_t u32;
	char strbuf[STR_LEN], buf[PATH_MAX];
	void *TMP_substitute_table, *TMP_char_pri_table, *TMP_chain_pri_table;
	static char collate_encoding[ENCODING_LEN + 1];

	/* 'encoding' must be already checked. */
	if (strcmp(encoding, "C") == 0 || strcmp(encoding, "POSIX") == 0) {
		__collate_load_error = 1;
		return (_LDP_CACHE);
	}

	/*
	 * If the locale name is the same as our cache, use the cache.
	 */
	if (strcmp(encoding, collate_encoding) == 0) {
		__collate_load_error = 0;
		return (_LDP_CACHE);
	}

	/*
	 * Slurp the locale file into the cache.
	 */

    ld = __crystax_locale_get_data(LC_COLLATE, encoding);
    if (ld == NULL)
        return (_LDP_ERROR);

    (void)strncpy(strbuf, ld->data, sizeof(strbuf));
    fpos = sizeof(strbuf);
	chains = -1;
	if (strcmp(strbuf, COLLATE_VERSION) == 0)
		chains = 0;
	else if (strcmp(strbuf, COLLATE_VERSION1_2) == 0)
		chains = 1;
	if (chains < 0) {
		errno = EFTYPE;
		return (_LDP_ERROR);
	}
	if (chains) {
        u32 = *(uint32_t *)(ld->data + fpos);
        fpos += sizeof(u32);
		if ((chains = (int)ntohl(u32)) < 1) {
			errno = EFTYPE;
			return (_LDP_ERROR);
		}
	} else
		chains = TABLE_SIZE;

	if ((TMP_substitute_table =
	     malloc(sizeof(__collate_substitute_table))) == NULL) {
		saverr = errno;
		errno = saverr;
		return (_LDP_ERROR);
	}
	if ((TMP_char_pri_table =
	     malloc(sizeof(__collate_char_pri_table))) == NULL) {
		saverr = errno;
		free(TMP_substitute_table);
		errno = saverr;
		return (_LDP_ERROR);
	}
	if ((TMP_chain_pri_table =
	     malloc(sizeof(*__collate_chain_pri_table) * chains)) == NULL) {
		saverr = errno;
		free(TMP_substitute_table);
		free(TMP_char_pri_table);
		errno = saverr;
		return (_LDP_ERROR);
	}

#define FREAD(a, b) \
{ \
    memmove(a, ld->data + fpos, b); \
    fpos += b; \
}

	FREAD(TMP_substitute_table, sizeof(__collate_substitute_table));
	FREAD(TMP_char_pri_table, sizeof(__collate_char_pri_table));
	FREAD(TMP_chain_pri_table, sizeof(*__collate_chain_pri_table) * chains);

	(void)strcpy(collate_encoding, encoding);
	if (__collate_substitute_table_ptr != NULL)
		free(__collate_substitute_table_ptr);
	__collate_substitute_table_ptr = TMP_substitute_table;
	if (__collate_char_pri_table_ptr != NULL)
		free(__collate_char_pri_table_ptr);
	__collate_char_pri_table_ptr = TMP_char_pri_table;
	for (i = 0; (unsigned)i < UCHAR_MAX + 1; i++) {
		__collate_char_pri_table[i].prim =
		    ntohl(__collate_char_pri_table[i].prim);
		__collate_char_pri_table[i].sec =
		    ntohl(__collate_char_pri_table[i].sec);
	}
	if (__collate_chain_pri_table != NULL)
		free(__collate_chain_pri_table);
	__collate_chain_pri_table = TMP_chain_pri_table;
	for (i = 0; i < chains; i++) {
		__collate_chain_pri_table[i].prim =
		    ntohl(__collate_chain_pri_table[i].prim);
		__collate_chain_pri_table[i].sec =
		    ntohl(__collate_chain_pri_table[i].sec);
	}
	__collate_substitute_nontrivial = 0;
	for (i = 0; (unsigned)i < UCHAR_MAX + 1; i++) {
		if (__collate_substitute_table[i][0] != i ||
		    __collate_substitute_table[i][1] != 0) {
			__collate_substitute_nontrivial = 1;
			break;
		}
	}
	__collate_load_error = 0;

	return (_LDP_LOADED);
}

u_char *
__collate_substitute(const u_char *s)
{
	int dest_len, len, nlen;
	int delta = strlen((const char *)s);
	u_char *dest_str = NULL;

	if (s == NULL || *s == '\0')
		return (__collate_strdup((u_char*)""));
	delta += delta / 8;
	dest_str = malloc(dest_len = delta);
	if (dest_str == NULL)
		__collate_err(EX_OSERR, __func__);
	len = 0;
	while (*s) {
		nlen = len + strlen((const char *)__collate_substitute_table[*s]);
		if (dest_len <= nlen) {
			dest_str = reallocf(dest_str, dest_len = nlen + delta);
			if (dest_str == NULL)
				__collate_err(EX_OSERR, __func__);
		}
		(void)strcpy((char*)dest_str + len, (const char *)__collate_substitute_table[*s++]);
		len = nlen;
	}
	return (dest_str);
}

void
__collate_lookup(const u_char *t, int *len, int *prim, int *sec)
{
	struct __collate_st_chain_pri *p2;

	*len = 1;
	*prim = *sec = 0;
	for (p2 = __collate_chain_pri_table; p2->str[0] != '\0'; p2++) {
		if (*t == p2->str[0] &&
		    strncmp((const char *)t, (const char *)p2->str, strlen((const char *)p2->str)) == 0) {
			*len = strlen((const char *)p2->str);
			*prim = p2->prim;
			*sec = p2->sec;
			return;
		}
	}
	*prim = __collate_char_pri_table[*t].prim;
	*sec = __collate_char_pri_table[*t].sec;
}

u_char *
__collate_strdup(u_char *s)
{
	u_char *t = (u_char *)strdup((const char *)s);

	if (t == NULL)
		__collate_err(EX_OSERR, __func__);
	return (t);
}

void
__collate_err(int ex, const char *f)
{
	const char *s;
	int serrno = errno;

	s = __crystax_getprogname();
	write(STDERR_FILENO, s, strlen(s));
	write(STDERR_FILENO, ": ", 2);
	s = f;
	write(STDERR_FILENO, s, strlen(s));
	write(STDERR_FILENO, ": ", 2);
	s = strerror(serrno);
	write(STDERR_FILENO, s, strlen(s));
	write(STDERR_FILENO, "\n", 1);
	exit(ex);
}

#ifdef COLLATE_DEBUG
void
__collate_print_tables()
{
	int i;
	struct __collate_st_chain_pri *p2;

	printf("Substitute table:\n");
	for (i = 0; i < UCHAR_MAX + 1; i++)
	    if (i != *__collate_substitute_table[i])
		printf("\t'%c' --> \"%s\"\n", i,
		       __collate_substitute_table[i]);
	printf("Chain priority table:\n");
	for (p2 = __collate_chain_pri_table; p2->str[0] != '\0'; p2++)
		printf("\t\"%s\" : %d %d\n", p2->str, p2->prim, p2->sec);
	printf("Char priority table:\n");
	for (i = 0; i < UCHAR_MAX + 1; i++)
		printf("\t'%c' : %d %d\n", i, __collate_char_pri_table[i].prim,
		       __collate_char_pri_table[i].sec);
}
#endif
