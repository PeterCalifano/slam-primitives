/// @file identifiers.h
/// @brief Defines distinct set, track, and frame identifiers and checked conversions.

#pragma once

#include <compare>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <limits>
#include <stdexcept>
#include <type_traits>

namespace slam_primitives
{

    using SetID = std::uint64_t;  ///< Generic feature-set identifier.
    using FrameID = std::int32_t; ///< Legacy signed frame identifier for checked conversion.

    /// @brief Convert a generic set ID to a 32-bit legacy field without truncation.
    /// @param id Generic feature-set identifier.
    /// @return The same value in the narrower field.
    /// @throws std::overflow_error If @p id exceeds the 32-bit range.
    [[nodiscard]] constexpr auto checkedSetIDToUint32(SetID id) -> std::uint32_t
    {
        if (id > std::numeric_limits<std::uint32_t>::max())
        {
            throw std::overflow_error("SetID exceeds the 32-bit range");
        }
        return static_cast<std::uint32_t>(id);
    }

    /// @brief Typed identifier for one feature track.
    ///
    /// Track IDs share the 64-bit numeric range of generic set IDs but form a
    /// distinct C++ type. A track-aware boundary must establish their meaning.
    class CFeatureTrackID final
    {
      public:
        using ValueType = std::uint64_t; ///< Unsigned storage for track identity.

        // CONSTRUCTORS
        /// @brief Construct a feature-track identifier from its unsigned value.
        /// @param value Identifier value.
        explicit constexpr CFeatureTrackID(ValueType value) noexcept : value_(value) {}

        // GETTERS
        /// @brief Return the stored unsigned value.
        /// @return Identifier value.
        [[nodiscard]] constexpr auto value() const noexcept -> ValueType
        {
            return value_;
        }

        /// @brief Convert to a 32-bit legacy field without truncation.
        /// @return The same track ID in the narrower field.
        /// @throws std::overflow_error If the track ID exceeds the 32-bit range.
        [[nodiscard]] constexpr auto toUint32() const -> std::uint32_t
        {
            if (value_ > std::numeric_limits<std::uint32_t>::max())
            {
                throw std::overflow_error("CFeatureTrackID exceeds the 32-bit range");
            }
            return static_cast<std::uint32_t>(value_);
        }

        /// @brief Compare feature-track identifiers by their stored values.
        /// @param other Feature-track identifier to compare against.
        /// @return Strong ordering of the stored identifier values.
        auto operator<=>(const CFeatureTrackID &other) const = default;

      private:
        // PRIVATE DATA MEMBERS
        ValueType value_;
    };

    /// @brief Typed identifier for one image or camera frame.
    ///
    /// Unlike the legacy signed `FrameID` alias, every `CFrameID` is valid. The
    /// explicit boundary functions reject negative legacy sentinels and overflow
    /// when converting a larger strong value back to the legacy representation.
    class CFrameID final
    {
      public:
        using ValueType = std::uint32_t; ///< Unsigned storage type for valid frame IDs.

        // CONSTRUCTORS
        /// @brief Construct the first valid frame identifier, frame zero.
        constexpr CFrameID() noexcept = default;

        /// @brief Construct a frame identifier from an integral value without narrowing.
        /// @param value Identifier value.
        /// @throws std::invalid_argument If @p value is negative.
        /// @throws std::overflow_error If @p value exceeds the 32-bit frame range.
        template <std::integral Integral>
            requires(!std::same_as<Integral, bool>)
        explicit constexpr CFrameID(Integral value) noexcept(std::same_as<Integral, ValueType>)
        {
            if constexpr (!std::same_as<Integral, ValueType>)
            {
                if constexpr (std::signed_integral<Integral>)
                {
                    if (value < 0)
                    {
                        throw std::invalid_argument("CFrameID: negative frame ID");
                    }
                }
                if (static_cast<std::make_unsigned_t<Integral>>(value) >
                    std::numeric_limits<ValueType>::max())
                {
                    throw std::overflow_error("CFrameID: frame ID exceeds 32-bit range");
                }
            }
            value_ = static_cast<ValueType>(value);
        }

        /// @brief Convert a legacy signed frame identifier after validation.
        /// @param legacy_id Legacy frame identifier.
        /// @return Typed identifier carrying the same nonnegative value.
        /// @throws std::invalid_argument If @p legacy_id is negative.
        [[nodiscard]] static constexpr auto fromLegacy(FrameID legacy_id) -> CFrameID
        {
            if (legacy_id < 0)
            {
                throw std::invalid_argument("CFrameID::fromLegacy: negative frame ID");
            }
            return CFrameID{static_cast<ValueType>(legacy_id)};
        }

        // GETTERS
        /// @brief Return the stored unsigned value.
        /// @return Identifier value.
        [[nodiscard]] constexpr auto value() const noexcept -> ValueType
        {
            return value_;
        }

        /// @brief Convert to the legacy signed representation after range checking.
        /// @return Legacy frame identifier carrying the same value.
        /// @throws std::overflow_error If the value exceeds the legacy signed range.
        [[nodiscard]] constexpr auto toLegacy() const -> FrameID
        {
            if (value_ > static_cast<ValueType>(std::numeric_limits<FrameID>::max()))
            {
                throw std::overflow_error("CFrameID::toLegacy: frame ID exceeds legacy range");
            }
            return static_cast<FrameID>(value_);
        }

        /// @brief Compare frame identifiers by their stored values.
        /// @param other Frame identifier to compare against.
        /// @return Strong ordering of the stored identifier values.
        auto operator<=>(const CFrameID &other) const = default;

      private:
        // PRIVATE DATA MEMBERS
        ValueType value_{0};
    };

} // namespace slam_primitives

namespace std
{
    /// @brief Hash a feature-track ID by its stored unsigned value.
    template <> struct hash<slam_primitives::CFeatureTrackID>
    {
        [[nodiscard]] auto
        operator()(slam_primitives::CFeatureTrackID id) const noexcept -> std::size_t
        {
            return std::hash<slam_primitives::CFeatureTrackID::ValueType>{}(id.value());
        }
    };
} // namespace std

namespace slam_primitives
{

    /// @brief Constraint for IDs used by feature sets, tracks, and their bundles.
    /// Requires ordered, hashable values constructible explicitly from the bundle counter.
    template <typename IDT>
    concept BundleIdentifier =
        std::copyable<IDT> && std::totally_ordered<IDT> && std::constructible_from<IDT, SetID> &&
        (std::same_as<IDT, SetID> || !std::convertible_to<SetID, IDT>) && requires(IDT id) {
            { std::hash<IDT>{}(id) } -> std::convertible_to<std::size_t>;
        } && (std::same_as<IDT, SetID> || requires(IDT id) {
            { id.value() } -> std::same_as<SetID>;
        });

} // namespace slam_primitives
