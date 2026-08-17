/// @file CLogger.h
/// @brief Provides a small dependency-free header-only C++20 logger.
/// @details Formats complete component-scoped lines and emits them atomically
///          through std::osyncstream without changing the library's
///          header-only target model.

#pragma once

#include <algorithm>
#include <atomic>
#include <cctype>
#include <concepts>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <ostream>
#include <sstream>
#include <string>
#include <string_view>
#include <syncstream>
#include <utility>

namespace slam_primitives::logging
{

/// @brief Ordered logging threshold used by CLogger.
///
/// Larger values enable progressively more verbose messages. Quiet disables
/// all output, while Trace enables every supported severity.
enum class ELogLevel : std::uint8_t
{
    Quiet = 0,
    Critical = 1,
    Error = 2,
    Warning = 3,
    Info = 4,
    Debug = 5,
    Trace = 6
};

/// @brief Select whether CLogger emits ANSI terminal color sequences.
enum class ELogColorMode : std::uint8_t
{
    Disabled = 0,
    Enabled = 1
};

/// @brief A value that can be appended to a standard output stream.
template <typename TValue>
concept StreamInsertable =
    requires(std::ostream &objStream_, TValue &&value_)
{
    objStream_ << std::forward<TValue>(value_);
};

/// @brief Small dependency-free component-scoped logger.
/// @details CLogger formats a complete line before atomically emitting it
///          through std::osyncstream. Critical, error, and warning messages use
///          the diagnostic stream; info, debug, and trace messages use the
///          ordinary output stream. Callers that provide custom streams must
///          keep them alive for the logger's lifetime.
class CLogger final
{
  public:
    /// @brief Construct a logger for one component.
    /// @param charComponentName Component printed in each line. An empty name
    ///        is replaced with `slam-primitives`.
    /// @param enumLevel Initial verbosity threshold.
    /// @param enumColorMode Explicit ANSI color policy.
    /// @param objOutputStream Stream for info, debug, and trace messages.
    /// @param objDiagnosticStream Stream for critical, error, and warning
    ///        messages.
    explicit CLogger(
        std::string charComponentName,
        ELogLevel enumLevel = ELogLevel::Error,
        ELogColorMode enumColorMode = ELogColorMode::Disabled,
        std::ostream &objOutputStream = std::cout,
        std::ostream &objDiagnosticStream = std::clog)
        : charComponentName_(
              charComponentName.empty() ? "slam-primitives"
                                        : std::move(charComponentName)),
          enumLevel_(enumLevel),
          enumColorMode_(enumColorMode),
          objOutputStream_(objOutputStream),
          objDiagnosticStream_(objDiagnosticStream)
    {
    }

    CLogger(const CLogger &) = delete;
    CLogger &operator=(const CLogger &) = delete;
    CLogger(CLogger &&) = delete;
    CLogger &operator=(CLogger &&) = delete;
    ~CLogger() = default;

    /// @brief Change the active verbosity threshold.
    void setLevel(const ELogLevel enumLevel) noexcept
    {
        enumLevel_.store(enumLevel, std::memory_order_relaxed);
    }

    /// @brief Return the active verbosity threshold.
    [[nodiscard]] ELogLevel getLevel() const noexcept
    {
        return enumLevel_.load(std::memory_order_relaxed);
    }

    /// @brief Return true when a severity is enabled by the active threshold.
    [[nodiscard]] bool shouldLog(const ELogLevel enumSeverity) const noexcept
    {
        const ELogLevel enumConfiguredLevel_ = getLevel();
        const auto uiConfiguredLevel_ =
            static_cast<std::uint8_t>(enumConfiguredLevel_);
        const auto uiSeverity_ =
            static_cast<std::uint8_t>(enumSeverity);

        if(enumConfiguredLevel_ == ELogLevel::Quiet ||
           enumSeverity == ELogLevel::Quiet)
        {
            return false;
        }

        // Reject invalid enum casts instead of treating them as thresholds
        // more verbose than Trace.
        if(uiConfiguredLevel_ >
               static_cast<std::uint8_t>(ELogLevel::Trace) ||
           uiSeverity_ > static_cast<std::uint8_t>(ELogLevel::Trace))
        {
            return false;
        }

        return uiSeverity_ <= uiConfiguredLevel_;
    }

    /// @brief Parse a case-insensitive level name or numeric value from 0 to 6.
    /// @param charLevelText Level text with optional surrounding ASCII space.
    /// @return Parsed level, or std::nullopt when the text is invalid.
    [[nodiscard]] static std::optional<ELogLevel>
    tryParseLevel(std::string_view charLevelText)
    {
        charLevelText = trimAsciiWhitespace_(charLevelText);
        if(charLevelText.size() == 1 &&
           charLevelText.front() >= '0' &&
           charLevelText.front() <= '6')
        {
            return static_cast<ELogLevel>(
                charLevelText.front() - '0');
        }

        std::string charNormalizedLevel_(charLevelText);
        std::ranges::transform(
            charNormalizedLevel_, charNormalizedLevel_.begin(),
            [](const unsigned char charValue_)
            {
                return static_cast<char>(std::tolower(charValue_));
            });

        if(charNormalizedLevel_ == "quiet" ||
           charNormalizedLevel_ == "off")
        {
            return ELogLevel::Quiet;
        }
        if(charNormalizedLevel_ == "critical" ||
           charNormalizedLevel_ == "fatal")
        {
            return ELogLevel::Critical;
        }
        if(charNormalizedLevel_ == "error")
        {
            return ELogLevel::Error;
        }
        if(charNormalizedLevel_ == "warning" ||
           charNormalizedLevel_ == "warn")
        {
            return ELogLevel::Warning;
        }
        if(charNormalizedLevel_ == "info")
        {
            return ELogLevel::Info;
        }
        if(charNormalizedLevel_ == "debug")
        {
            return ELogLevel::Debug;
        }
        if(charNormalizedLevel_ == "trace")
        {
            return ELogLevel::Trace;
        }
        return std::nullopt;
    }

    /// @brief Apply a valid level from an environment variable.
    /// @param charVariableName Environment variable to read.
    /// @return True only when a valid value was found and applied.
    bool setLevelFromEnvironment(
        const std::string_view charVariableName =
            "SLAM_PRIMITIVES_LOG_LEVEL")
    {
        if(charVariableName.empty())
        {
            return false;
        }

        // getenv requires a null-terminated name, while the public API accepts
        // a non-owning string view.
        const std::string charVariableNameCopy_(charVariableName);
        const char *charEnvironmentValue_ =
            std::getenv(charVariableNameCopy_.c_str());
        if(charEnvironmentValue_ == nullptr)
        {
            return false;
        }

        const std::optional<ELogLevel> enumParsedLevel_ =
            tryParseLevel(charEnvironmentValue_);
        if(!enumParsedLevel_.has_value())
        {
            return false;
        }

        setLevel(*enumParsedLevel_);
        return true;
    }

    /// @brief Emit a critical message when enabled.
    template <StreamInsertable... TArgs>
    void critical(TArgs &&...args)
    {
        write_(ELogLevel::Critical, std::forward<TArgs>(args)...);
    }

    /// @brief Emit an error message when enabled.
    template <StreamInsertable... TArgs>
    void error(TArgs &&...args)
    {
        write_(ELogLevel::Error, std::forward<TArgs>(args)...);
    }

    /// @brief Emit a warning message when enabled.
    template <StreamInsertable... TArgs>
    void warning(TArgs &&...args)
    {
        write_(ELogLevel::Warning, std::forward<TArgs>(args)...);
    }

    /// @brief Emit an informational message when enabled.
    template <StreamInsertable... TArgs>
    void info(TArgs &&...args)
    {
        write_(ELogLevel::Info, std::forward<TArgs>(args)...);
    }

    /// @brief Emit a debug message when enabled.
    template <StreamInsertable... TArgs>
    void debug(TArgs &&...args)
    {
        write_(ELogLevel::Debug, std::forward<TArgs>(args)...);
    }

    /// @brief Emit a trace message when enabled.
    template <StreamInsertable... TArgs>
    void trace(TArgs &&...args)
    {
        write_(ELogLevel::Trace, std::forward<TArgs>(args)...);
    }

  private:
    template <StreamInsertable... TArgs>
    void write_(const ELogLevel enumSeverity, TArgs &&...args)
    {
        if(!shouldLog(enumSeverity))
        {
            return;
        }

        // Assemble before synchronized emission so argument formatting does
        // not serialize independent logger calls.
        std::ostringstream objMessageStream_;
        (objMessageStream_ << ... << std::forward<TArgs>(args));
        writeMessage_(enumSeverity, objMessageStream_.str());
    }

    void writeMessage_(
        const ELogLevel enumSeverity,
        const std::string_view charMessage)
    {
        const bool bUseColor_ =
            enumColorMode_ == ELogColorMode::Enabled;

        std::ostringstream objFormattedLineStream_;
        if(bUseColor_)
        {
            objFormattedLineStream_ << getColorCode_(enumSeverity);
        }
        objFormattedLineStream_
            << '[' << charComponentName_ << "]["
            << getLevelLabel_(enumSeverity) << "] " << charMessage;
        if(bUseColor_)
        {
            objFormattedLineStream_ << charColorReset_;
        }
        objFormattedLineStream_ << '\n';

        // osyncstream coordinates instances that wrap the same destination
        // stream buffer and emits this complete line as one operation.
        std::osyncstream objSynchronizedStream_(
            selectStream_(enumSeverity));
        objSynchronizedStream_ << objFormattedLineStream_.str();
    }

    [[nodiscard]] std::ostream &
    selectStream_(const ELogLevel enumSeverity) const noexcept
    {
        if(enumSeverity == ELogLevel::Critical ||
           enumSeverity == ELogLevel::Error ||
           enumSeverity == ELogLevel::Warning)
        {
            return objDiagnosticStream_;
        }
        return objOutputStream_;
    }

    [[nodiscard]] static std::string_view
    trimAsciiWhitespace_(std::string_view charText)
    {
        while(!charText.empty() &&
              std::isspace(static_cast<unsigned char>(
                  charText.front())) != 0)
        {
            charText.remove_prefix(1);
        }
        while(!charText.empty() &&
              std::isspace(static_cast<unsigned char>(
                  charText.back())) != 0)
        {
            charText.remove_suffix(1);
        }
        return charText;
    }

    [[nodiscard]] static std::string_view
    getLevelLabel_(const ELogLevel enumSeverity) noexcept
    {
        switch(enumSeverity)
        {
        case ELogLevel::Critical:
            return "CRITICAL";
        case ELogLevel::Error:
            return "ERROR";
        case ELogLevel::Warning:
            return "WARNING";
        case ELogLevel::Info:
            return "INFO";
        case ELogLevel::Debug:
            return "DEBUG";
        case ELogLevel::Trace:
            return "TRACE";
        case ELogLevel::Quiet:
        default:
            return "QUIET";
        }
    }

    [[nodiscard]] static std::string_view
    getColorCode_(const ELogLevel enumSeverity) noexcept
    {
        switch(enumSeverity)
        {
        case ELogLevel::Critical:
            return charCriticalColor_;
        case ELogLevel::Error:
            return charErrorColor_;
        case ELogLevel::Warning:
            return charWarningColor_;
        case ELogLevel::Info:
            return charInfoColor_;
        case ELogLevel::Debug:
            return charDebugColor_;
        case ELogLevel::Trace:
            return charTraceColor_;
        case ELogLevel::Quiet:
        default:
            return {};
        }
    }

  private:
    inline static constexpr std::string_view charColorReset_ =
        "\033[0m";
    inline static constexpr std::string_view charCriticalColor_ =
        "\033[1;31m";
    inline static constexpr std::string_view charErrorColor_ =
        "\033[31m";
    inline static constexpr std::string_view charWarningColor_ =
        "\033[33m";
    inline static constexpr std::string_view charInfoColor_ =
        "\033[34m";
    inline static constexpr std::string_view charDebugColor_ =
        "\033[36m";
    inline static constexpr std::string_view charTraceColor_ =
        "\033[2m";

    std::string charComponentName_;
    std::atomic<ELogLevel> enumLevel_;
    ELogColorMode enumColorMode_;
    std::ostream &objOutputStream_;
    std::ostream &objDiagnosticStream_;
};

} // namespace slam_primitives::logging
