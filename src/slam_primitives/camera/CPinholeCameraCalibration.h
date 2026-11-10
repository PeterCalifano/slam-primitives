/// @file CPinholeCameraCalibration.h
/// @brief Defines a validated pinhole-camera intrinsic calibration.

#pragma once

#include "slam-primitives/types/feature_types.h"

#include <Eigen/Core>

#include <cmath>
#include <limits>
#include <stdexcept>

namespace slam_primitives
{

    /// @brief Immutable pinhole-camera intrinsic calibration.
    ///
    /// The stored matrix has the pinhole form
    /// `[fx, skew, cx; 0, fy, cy; 0, 0, 1]`, with finite values and positive
    /// focal lengths. Distortion is intentionally outside this primitive.
    class CPinholeCameraCalibration final
    {
      public:
        // CONSTRUCTORS
        /// @brief Construct and validate a pinhole intrinsic matrix.
        /// @param intrinsic_matrix Candidate camera intrinsic matrix.
        /// @throws std::invalid_argument If values are nonfinite, focal lengths
        ///         are nonpositive, or the matrix is not in pinhole form.
        explicit CPinholeCameraCalibration(const Eigen::Matrix3d &intrinsic_matrix)
            : intrinsic_matrix_(validateIntrinsicMatrix(intrinsic_matrix))
        {
        }

        // GETTERS
        /// @brief Return the validated camera intrinsic matrix.
        /// @return Read-only intrinsic matrix reference.
        [[nodiscard]] auto matrix() const noexcept -> const Eigen::Matrix3d &
        {
            return intrinsic_matrix_;
        }

        /// @brief Convert a finite pixel coordinate to an unnormalized camera
        ///        bearing.
        /// @param pixel Pixel coordinate in column/row convention.
        /// @return Camera-frame bearing `[x, y, 1]`.
        /// @throws std::invalid_argument If @p pixel is nonfinite.
        [[nodiscard]] auto unproject(const SFeatureLocation2D &pixel) const -> Eigen::Vector3d
        {
            if (!std::isfinite(pixel.u) || !std::isfinite(pixel.v))
            {
                throw std::invalid_argument(
                    "CPinholeCameraCalibration::unproject: pixel must be finite");
            }

            const double y = (pixel.v - intrinsic_matrix_(1, 2)) / intrinsic_matrix_(1, 1);
            const double x = (pixel.u - intrinsic_matrix_(0, 2) - intrinsic_matrix_(0, 1) * y) /
                             intrinsic_matrix_(0, 0);
            return Eigen::Vector3d{x, y, 1.0};
        }

      private:
        // PRIVATE METHODS
        [[nodiscard]] static auto
        validateIntrinsicMatrix(const Eigen::Matrix3d &intrinsic_matrix) -> Eigen::Matrix3d
        {
            // Reject invalid physical parameters before accepting small numerical
            // deviations from the required pinhole matrix layout.
            if (!intrinsic_matrix.allFinite())
            {
                throw std::invalid_argument(
                    "CPinholeCameraCalibration: intrinsic matrix must be finite");
            }
            if (intrinsic_matrix(0, 0) <= 0.0 || intrinsic_matrix(1, 1) <= 0.0)
            {
                throw std::invalid_argument(
                    "CPinholeCameraCalibration: focal lengths must be positive");
            }

            // Accept roundoff in the structural entries, then store their exact
            // pinhole values.
            constexpr double tolerance = 64.0 * std::numeric_limits<double>::epsilon();
            if (std::abs(intrinsic_matrix(1, 0)) > tolerance ||
                std::abs(intrinsic_matrix(2, 0)) > tolerance ||
                std::abs(intrinsic_matrix(2, 1)) > tolerance ||
                std::abs(intrinsic_matrix(2, 2) - 1.0) > tolerance)
            {
                throw std::invalid_argument(
                    "CPinholeCameraCalibration: matrix must have pinhole form");
            }

            Eigen::Matrix3d validated_matrix = intrinsic_matrix;
            validated_matrix(1, 0) = 0.0;
            validated_matrix(2, 0) = 0.0;
            validated_matrix(2, 1) = 0.0;
            validated_matrix(2, 2) = 1.0;
            return validated_matrix;
        }

        // PRIVATE DATA MEMBERS
        Eigen::Matrix3d intrinsic_matrix_;
    };

} // namespace slam_primitives
