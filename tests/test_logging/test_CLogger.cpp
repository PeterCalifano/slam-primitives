/// @file test_CLogger.cpp
/// @brief Verifies the dependency-free header-only logging contract.

#include "CLoggerOtherTranslationUnit.h"

#include <slam_primitives/logging/CLogger.h>

#include <catch2/catch_test_macros.hpp>

#include <cstdlib>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace
{
class CEnvironmentVariableGuard final
{
  public:
    explicit CEnvironmentVariableGuard(std::string charVariableName)
        : charVariableName_(std::move(charVariableName))
    {
        const char *charExistingValue_ =
            std::getenv(charVariableName_.c_str());
        if(charExistingValue_ != nullptr)
        {
            charPreviousValue_ = std::string(charExistingValue_);
        }
    }

    CEnvironmentVariableGuard(const CEnvironmentVariableGuard &) = delete;
    CEnvironmentVariableGuard &
    operator=(const CEnvironmentVariableGuard &) = delete;

    ~CEnvironmentVariableGuard()
    {
        if(charPreviousValue_.has_value())
        {
            setenv(charVariableName_.c_str(),
                   charPreviousValue_->c_str(), 1);
        }
        else
        {
            unsetenv(charVariableName_.c_str());
        }
    }

    void setValue(const std::string &charValue) const
    {
        setenv(charVariableName_.c_str(), charValue.c_str(), 1);
    }

  private:
    std::string charVariableName_;
    std::optional<std::string> charPreviousValue_;
};
} // namespace

TEST_CASE("CLogger filters levels and routes complete lines", "[logging]")
{
    using namespace slam_primitives::logging;

    std::ostringstream objOutputStream_;
    std::ostringstream objDiagnosticStream_;
    CLogger objLogger_("component", ELogLevel::Info,
                       ELogColorMode::Disabled, objOutputStream_,
                       objDiagnosticStream_);

    objLogger_.trace("hidden trace");
    objLogger_.debug("hidden debug");
    objLogger_.info("ready ", 3);
    objLogger_.warning("temperature ", 42.5);
    objLogger_.error("failed");
    objLogger_.critical("unsafe");

    REQUIRE(objOutputStream_.str() == "[component][INFO] ready 3\n");
    REQUIRE(objDiagnosticStream_.str() ==
            "[component][WARNING] temperature 42.5\n"
            "[component][ERROR] failed\n"
            "[component][CRITICAL] unsafe\n");
}

TEST_CASE("CLogger parses named and numeric levels", "[logging]")
{
    using namespace slam_primitives::logging;

    REQUIRE(CLogger::tryParseLevel(" quiet ") == ELogLevel::Quiet);
    REQUIRE(CLogger::tryParseLevel("CRITICAL") == ELogLevel::Critical);
    REQUIRE(CLogger::tryParseLevel("warning") == ELogLevel::Warning);
    REQUIRE(CLogger::tryParseLevel("DeBuG") == ELogLevel::Debug);
    REQUIRE(CLogger::tryParseLevel("0") == ELogLevel::Quiet);
    REQUIRE(CLogger::tryParseLevel("6") == ELogLevel::Trace);
    REQUIRE_FALSE(CLogger::tryParseLevel("verbose").has_value());
    REQUIRE_FALSE(CLogger::tryParseLevel("7").has_value());
}

TEST_CASE("CLogger rejects invalid severity values", "[logging]")
{
    using namespace slam_primitives::logging;

    CLogger objLogger_("component", ELogLevel::Trace);
    REQUIRE_FALSE(
        objLogger_.shouldLog(static_cast<ELogLevel>(255)));

    objLogger_.setLevel(static_cast<ELogLevel>(255));
    REQUIRE_FALSE(objLogger_.shouldLog(ELogLevel::Error));
}

TEST_CASE("CLogger reads its tailored environment variable", "[logging]")
{
    using namespace slam_primitives::logging;

    CEnvironmentVariableGuard objEnvironmentGuard_(
        "SLAM_PRIMITIVES_LOG_LEVEL");
    std::ostringstream objOutputStream_;
    std::ostringstream objDiagnosticStream_;
    CLogger objLogger_("component", ELogLevel::Info,
                       ELogColorMode::Disabled, objOutputStream_,
                       objDiagnosticStream_);

    objEnvironmentGuard_.setValue("trace");
    REQUIRE(objLogger_.setLevelFromEnvironment());
    REQUIRE(objLogger_.getLevel() == ELogLevel::Trace);

    objEnvironmentGuard_.setValue("invalid");
    REQUIRE_FALSE(objLogger_.setLevelFromEnvironment());
    REQUIRE(objLogger_.getLevel() == ELogLevel::Trace);
}

TEST_CASE("CLogger color and default component are explicit", "[logging]")
{
    using namespace slam_primitives::logging;

    std::ostringstream objOutputStream_;
    std::ostringstream objDiagnosticStream_;
    CLogger objLogger_("", ELogLevel::Info, ELogColorMode::Enabled,
                       objOutputStream_, objDiagnosticStream_);
    objLogger_.info("ready");

    REQUIRE(objOutputStream_.str() ==
            "\033[34m[slam-primitives][INFO] ready\033[0m\n");
    REQUIRE(objDiagnosticStream_.str().empty());
}

TEST_CASE("CLogger instances serialize concurrent writes as complete lines",
          "[logging]")
{
    using namespace slam_primitives::logging;

    constexpr std::size_t uiMessageCount_ = 16;
    std::ostringstream objOutputStream_;
    std::ostringstream objDiagnosticStream_;
    std::vector<std::thread> objThreads_;

    objThreads_.reserve(uiMessageCount_);
    for(std::size_t uiMessageIndex_ = 0;
        uiMessageIndex_ < uiMessageCount_; ++uiMessageIndex_)
    {
        objThreads_.emplace_back(
            [&objOutputStream_, &objDiagnosticStream_,
             uiMessageIndex_]()
            {
                CLogger objLogger_(
                    "worker", ELogLevel::Info,
                    ELogColorMode::Disabled, objOutputStream_,
                    objDiagnosticStream_);
                objLogger_.info("message-", uiMessageIndex_);
            });
    }
    for(std::thread &objThread_ : objThreads_)
    {
        objThread_.join();
    }

    std::set<std::string> charActualLines_;
    std::size_t uiActualLineCount_ = 0;
    std::istringstream objCapturedOutput_(objOutputStream_.str());
    for(std::string charLine_;
        std::getline(objCapturedOutput_, charLine_);)
    {
        ++uiActualLineCount_;
        charActualLines_.insert(charLine_);
    }

    std::set<std::string> charExpectedLines_;
    for(std::size_t uiMessageIndex_ = 0;
        uiMessageIndex_ < uiMessageCount_; ++uiMessageIndex_)
    {
        charExpectedLines_.insert(
            "[worker][INFO] message-" +
            std::to_string(uiMessageIndex_));
    }

    REQUIRE(uiActualLineCount_ == uiMessageCount_);
    REQUIRE(charActualLines_ == charExpectedLines_);
}

TEST_CASE("CLogger is link-safe across translation units", "[logging]")
{
    REQUIRE(LogFromOtherTranslationUnit() ==
            "[other][INFO] translation-unit\n");
}
