package com.softthrive.inventory_app

import androidx.core.content.FileProvider

/** Own provider class so it never clashes with plugin FileProviders. */
class PdfFileProvider : FileProvider()
