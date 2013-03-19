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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <config.h>
#include "mar.h"
#include "mar_cmdline.h"

#ifdef XP_WIN
#include <windows.h>
#include <direct.h>
#define chdir _chdir
#else
#include <unistd.h>
#endif

static void print_usage() {
  printf("usage:\n");
  printf("Create a MAR file:\n");
  printf("  mar [-H MARChannelID] [-V ProductVersion] [-C workingDir] "
         "{-c|-x|-t|-T} archive.mar [files...]\n");
  printf("Print information on a MAR file:\n");
  printf("  mar [-H MARChannelID] [-V ProductVersion] [-C workingDir] "
         "-i unsigned_archive_to_refresh.mar\n");
  printf("This program does not handle unicode file paths properly\n");
}

static int mar_test_callback(MarFile *mar, 
                             const MarItem *item, 
                             void *unused) {
  printf("%u\t0%o\t%s\n", item->length, item->flags, item->name);
  return 0;
}

static int mar_test(const char *path) {
  MarFile *mar;

  mar = mar_open(path);
  if (!mar)
    return -1;

  printf("SIZE\tMODE\tNAME\n");
  mar_enum_items(mar, mar_test_callback, NULL);

  mar_close(mar);
  return 0;
}

int main(int argc, char **argv) {
  char *MARChannelID = MAR_CHANNEL_ID;
  char *productVersion = MOZ_APP_VERSION;
  uint32_t i, k;
  int rv = -1;

  if (argc < 3) {
    print_usage();
    return -1;
  }

  while (argc > 0) {
    if (argv[1][0] == '-' && (argv[1][1] == 'c' || 
        argv[1][1] == 't' || argv[1][1] == 'x' || 
        argv[1][1] == 'i' || argv[1][1] == 'T')) {
      break;
    /* -C workingdirectory */
    } else if (argv[1][0] == '-' && argv[1][1] == 'C') {
      chdir(argv[2]);
      argv += 2;
      argc -= 2;
    /* MAR channel ID */
    } else if (argv[1][0] == '-' && argv[1][1] == 'H') {
      MARChannelID = argv[2];
      argv += 2;
      argc -= 2;
    /* Product Version */
    } else if (argv[1][0] == '-' && argv[1][1] == 'V') {
      productVersion = argv[2];
      argv += 2;
      argc -= 2;
    }
    else {
      print_usage();
      return -1;
    }
  }

  if (argv[1][0] != '-') {
    print_usage();
    return -1;
  }

  switch (argv[1][1]) {
  case 'c': {
    struct ProductInformationBlock infoBlock;
    infoBlock.MARChannelID = MARChannelID;
    infoBlock.productVersion = productVersion;
    return mar_create(argv[2], argc - 3, argv + 3, &infoBlock);
  }
  case 'i': {
    struct ProductInformationBlock infoBlock;
    infoBlock.MARChannelID = MARChannelID;
    infoBlock.productVersion = productVersion;
    return refresh_product_info_block(argv[2], &infoBlock);
  }
  case 'T': {
    struct ProductInformationBlock infoBlock;
    uint32_t numSignatures, numAdditionalBlocks;
    int hasSignatureBlock, hasAdditionalBlock;
    if (!get_mar_file_info(argv[2], 
                           &hasSignatureBlock,
                           &numSignatures,
                           &hasAdditionalBlock, 
                           NULL, &numAdditionalBlocks)) {
      if (hasSignatureBlock) {
        printf("Signature block found with %d signature%s\n", 
               numSignatures, 
               numSignatures != 1 ? "s" : "");
      }
      if (hasAdditionalBlock) {
        printf("%d additional block%s found:\n", 
               numAdditionalBlocks,
               numAdditionalBlocks != 1 ? "s" : "");
      }

      rv = read_product_info_block(argv[2], &infoBlock);
      if (!rv) {
        printf("  - Product Information Block:\n");
        printf("    - MAR channel name: %s\n"
               "    - Product version: %s\n",
               infoBlock.MARChannelID,
               infoBlock.productVersion);
        free((void *)infoBlock.MARChannelID);
        free((void *)infoBlock.productVersion);
      }
     }
    printf("\n");
    /* The fall through from 'T' to 't' is intentional */
  }
  case 't':
    return mar_test(argv[2]);

  /* Extract a MAR file */
  case 'x':
    return mar_extract(argv[2]);

  default:
    print_usage();
    return -1;
  }

  return 0;
}
