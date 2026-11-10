/// @file CImagePointObservation.h
/// @brief Defines a validated pixel observation with measurement uncertainty.

#pragma once

#include "slam-primitives/types/identifiers.h"
#include "slam-primitives/types/feature_types.h"
#include "slam-primitives/detail/covariance_validation.h"

#include <Eigen/Core>

#include <cmath>
#include <stdexcept>

namespace slam_primitives
{

    /// @brief Immutable two-dimensional image observation associated with one frame.
    ///
    /// Pixel covariance is expressed in `[u, v]` pixel coordinates and is checked
    /// for finite, symmetric, positive-semidefinite values during construction.
    class CImagePointObservation final
    {
      public:
        // CONSTRUCTORS
        /// @brief Construct and validate an image observation.
        /// @param frame_id Frame in which the observation was acquired.
        /// @param pixel Pixel coordinate in column/row convention.
        /// @param pixel_covariance Pixel covariance in `[u, v]` coordinates.
        /// @throws std::invalid_argument If the pixel or covariance violates the
        ///         finite, symmetry, or positive-semidefinite contract.
        CImagePointObservation(CFrameID frame_id, SFeatureLocation2D pixel,
                               const Eigen::Matrix2d &pixel_covariance)
            : frame_id_(frame_id), pixel_(validatePixel(pixel)),
              pixel_covariance_(validateCovariance(pixel_covariance))
        {
        }

        // GETTERS
        /// @brief Return the observation frame identifier.
        /// @return Strong frame identifier.
        [[nodiscard]] auto getFrameID() const noexcept -> CFrameID
        {
            return frame_id_;
        }

        /// @brief Return the pixel coordinate.
        /// @return Read-only pixel reference.
        [[nodiscard]] auto pixel() const noexcept -> const SFeatureLocation2D &
        {
            return pixel_;
        }

        /// @brief Return pixel covariance in `[u, v]` coordinates.
        /// @return Read-only covariance reference.
        [[nodiscard]] auto pixelCovariance() const noexcept -> const Eigen::Matrix2d &
        {
            return pixel_covariance_;
        }

      private:
        // PRIVATE METHODS
        [[nodiscard]] static auto validatePixel(SFeatureLocation2D pixel) -> SFeatureLocation2D
        {
            if (!std::isfinite(pixel.u) || !std::isfinite(pixel.v))
            {
                throw std::invalid_argument("CImagePointObservation: pixel must be finite");
            }
            return pixel;
        }

        [[nodiscard]] static auto
        validateCovariance(const Eigen::Matrix2d &pixel_covariance) -> Eigen::Matrix2d
        {
            return detail::validateCovariance(pixel_covariance);
        }

        // PRIVATE DATA MEMBERS
        CFrameID frame_id_;
        SFeatureLocation2D pixel_;
        Eigen::Matrix2d pixel_covariance_;
    };

} // namespace slam_primitives
