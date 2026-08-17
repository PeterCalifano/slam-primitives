/// @file CLoggerOtherTranslationUnit.cpp
/// @brief Defines the cross-translation-unit logger test helper.

#include "CLoggerOtherTranslationUnit.h"

#include <slam_primitives/logging/CLogger.h>

#include <sstream>

std::string LogFromOtherTranslationUnit()
{
    std::ostringstream objOutputStream_;
    std::ostringstream objDiagnosticStream_;
    slam_primitives::logging::CLogger objLogger_(
        "other", slam_primitives::logging::ELogLevel::Info,
        slam_primitives::logging::ELogColorMode::Disabled, objOutputStream_,
        objDiagnosticStream_);
    objLogger_.info("translation-unit");
    return objOutputStream_.str();
}
