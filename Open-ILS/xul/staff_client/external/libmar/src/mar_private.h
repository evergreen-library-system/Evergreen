/* -*- Mode: C; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim:set ts=2 sw=2 sts=2 et cindent: */
/*
 * This file is part of Evergreen.
 *
 * Evergreen is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 2 of the License,
 * or (at your option) any later version.
 *
 * Evergreen is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Evergreen.  If not, see <http://www.gnu.org/licenses/>.
 *
 * This Source Code Form is derived from code that was originally
 * subject to the terms of the Mozilla Public License, v. 2.0 and
 * included in Evergreen.  You may, therefore, use this Source Code
 * Form under the terms of the Mozilla Public License 2.0.  This
 * licensing option does not affect the larger Evergreen project, only
 * the Source Code Forms bearing this exception are affected.  If a
 * copy of the MPL was not distributed with this file, You can obtain
 * one at http://mozilla.org/MPL/2.0/.
 */

#ifndef MAR_PRIVATE_H__
#define MAR_PRIVATE_H__

#include <stdint.h>

#define BLOCKSIZE 4096
#define ROUND_UP(n, incr) (((n) / (incr) + 1) * (incr))

#define MAR_ID "MAR1"
#define MAR_ID_SIZE 4

/* The signature block comes directly after the header block 
   which is 16 bytes */
#define SIGNATURE_BLOCK_OFFSET 16

/* Make sure the file is less than 500MB.  We do this to protect against
   invalid MAR files. */
#define MAX_SIZE_OF_MAR_FILE ((int64_t)524288000)

/* The maximum size of any signature supported by current and future
   implementations of the signmar program. */
#define MAX_SIGNATURE_LENGTH 2048

/* Each additional block has a unique ID.  
   The product information block has an ID of 1. */
#define PRODUCT_INFO_BLOCK_ID 1

#define MAR_ITEM_SIZE(namelen) (3*sizeof(uint32_t) + (namelen) + 1)

/* Product Information Block (PIB) constants */
#define PIB_MAX_MAR_CHANNEL_ID_SIZE 63
#define PIB_MAX_PRODUCT_VERSION_SIZE 31

/* The mar program is compiled as a host bin so we don't have access to NSPR at
   runtime.  For that reason we use ntohl, htonl, and define HOST_TO_NETWORK64 
   instead of the NSPR equivalents. */
#ifdef XP_WIN
#include <winsock2.h>
#define ftello _ftelli64
#define fseeko _fseeki64
#else
#define _FILE_OFFSET_BITS 64
#include <netinet/in.h>
#include <unistd.h>
#endif

#include <stdio.h>

#define HOST_TO_NETWORK64(x) ( \
  ((((uint64_t) x) & 0xFF) << 56) | \
  ((((uint64_t) x) >> 8) & 0xFF) << 48) | \
  (((((uint64_t) x) >> 16) & 0xFF) << 40) | \
  (((((uint64_t) x) >> 24) & 0xFF) << 32) | \
  (((((uint64_t) x) >> 32) & 0xFF) << 24) | \
  (((((uint64_t) x) >> 40) & 0xFF) << 16) | \
  (((((uint64_t) x) >> 48) & 0xFF) << 8) | \
  (((uint64_t) x) >> 56)
#define NETWORK_TO_HOST64 HOST_TO_NETWORK64

#endif  /* MAR_PRIVATE_H__ */
