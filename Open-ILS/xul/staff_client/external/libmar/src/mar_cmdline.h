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

#ifndef MAR_CMDLINE_H__
#define MAR_CMDLINE_H__

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct ProductInformationBlock;

/**
 * Determines MAR file information.
 *
 * @param path                   The path of the MAR file to check.
 * @param hasSignatureBlock      Optional out parameter specifying if the MAR
 *                               file has a signature block or not.
 * @param numSignatures          Optional out parameter for storing the number
 *                               of signatures in the MAR file.
 * @param hasAdditionalBlocks    Optional out parameter specifying if the MAR
 *                               file has additional blocks or not.
 * @param offsetAdditionalBlocks Optional out parameter for the offset to the 
 *                               first additional block. Value is only valid if
 *                               hasAdditionalBlocks is not equal to 0.
 * @param numAdditionalBlocks    Optional out parameter for the number of
 *                               additional blocks.  Value is only valid if
 *                               has_additional_blocks is not equal to 0.
 * @return 0 on success and non-zero on failure.
 */
int get_mar_file_info(const char *path, 
                      int *hasSignatureBlock,
                      uint32_t *numSignatures,
                      int *hasAdditionalBlocks,
                      uint32_t *offsetAdditionalBlocks,
                      uint32_t *numAdditionalBlocks);

/** 
 * Reads the product info block from the MAR file's additional block section.
 * The caller is responsible for freeing the fields in infoBlock
 * if the return is successful.
 *
 * @param infoBlock Out parameter for where to store the result to
 * @return 0 on success, -1 on failure
*/
int
read_product_info_block(char *path, 
                        struct ProductInformationBlock *infoBlock);

/** 
 * Refreshes the product information block with the new information.
 * The input MAR must not be signed or the function call will fail.
 * 
 * @param path             The path to the MAR file whose product info block
 *                         should be refreshed.
 * @param infoBlock        Out parameter for where to store the result to
 * @return 0 on success, -1 on failure
*/
int
refresh_product_info_block(const char *path,
                           struct ProductInformationBlock *infoBlock);

#ifdef __cplusplus
}
#endif

#endif  /* MAR_CMDLINE_H__ */
