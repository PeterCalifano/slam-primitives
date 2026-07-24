/// @file CLoggerOtherTranslationUnit.h
/// @brief Declares the cross-translation-unit logger test helper.

#pragma once

#include <string>

/// @brief Exercise CLogger from a translation unit separate from its tests.
/// @return One formatted informational log line.
[[nodiscard]] std::string LogFromOtherTranslationUnit();
