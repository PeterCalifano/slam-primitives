/// @file CCameraView.h
/// @brief Defines validated camera geometry and optional pose uncertainty.

#pragma once

#include "slam-primitives/types/identifiers.h"
#include "slam-primitives/camera/CPinholeCameraCalibration.h"
#include "slam-primitives/detail/covariance_validation.h"

#include <Eigen/Core>
#include <Eigen/LU>

#include <cmath>
#include <optional>
#include <stdexcept>
#include <utility>

namespace slam_primitives
{

    /// @brief Immutable calibrated camera view expressed relative to world frame `W`.
    ///
    /// The pose convention is explicit: `R_CW` rotates world vectors into camera
    /// coordinates and `c_W` is the camera center in `W`. Optional center
    /// covariance is expressed in `W`; optional small-angle attitude covariance
    /// is expressed in camera-local coordinates. Cross-covariance is intentionally
    /// not represented by this prototype primitive.
    class CCameraView final
    {
      public:
        // CONSTRUCTORS
        /// @brief Construct and validate a calibrated camera view.
        /// @param frame_id Strong frame identifier.
        /// @param calibration Validated pinhole calibration.
        /// @param rotation_CW Rotation from world frame `W` to camera frame `C`.
        /// @param camera_center_W Camera center expressed in `W`.
        /// @param camera_center_covariance_W Optional center covariance in `W`.
        /// @param attitude_covariance_C Optional camera-local attitude covariance.
        /// @throws std::invalid_argument If pose values are nonfinite, the rotation
        ///         is not proper orthonormal, or a supplied covariance is not
        ///         finite, symmetric, and positive semidefinite.
        CCameraView(CFrameID frame_id, CPinholeCameraCalibration calibration,
                    const Eigen::Matrix3d &rotation_CW, const Eigen::Vector3d &camera_center_W,
                    std::optional<Eigen::Matrix3d> camera_center_covariance_W = std::nullopt,
                    std::optional<Eigen::Matrix3d> attitude_covariance_C = std::nullopt)
            : frame_id_(frame_id), calibration_(std::move(calibration)),
              rotation_CW_(validateRotation(rotation_CW)),
              camera_center_W_(validateCenter(camera_center_W)),
              camera_center_covariance_W_(
                  validateCovariance(std::move(camera_center_covariance_W))),
              attitude_covariance_C_(validateCovariance(std::move(attitude_covariance_C)))
        {
        }

        // GETTERS
        /// @brief Return this view's frame identifier.
        /// @return Strong frame identifier.
        [[nodiscard]] auto getFrameID() const noexcept -> CFrameID
        {
            return frame_id_;
        }

        /// @brief Return the camera calibration.
        /// @return Read-only calibration reference.
        [[nodiscard]] auto calibration() const noexcept -> const CPinholeCameraCalibration &
        {
            return calibration_;
        }

        /// @brief Return `R_CW`, rotating world vectors into camera coordinates.
        /// @return Read-only rotation-matrix reference.
        [[nodiscard]] auto rotationCameraFromWorld() const noexcept -> const Eigen::Matrix3d &
        {
            return rotation_CW_;
        }

        /// @brief Return camera center `c_W`.
        /// @return Read-only world-frame camera-center reference.
        [[nodiscard]] auto cameraCenterWorld() const noexcept -> const Eigen::Vector3d &
        {
            return camera_center_W_;
        }

        /// @brief Return optional camera-center covariance expressed in `W`.
        /// @return Read-only optional covariance reference.
        [[nodiscard]] auto
        cameraCenterCovarianceWorld() const noexcept -> const std::optional<Eigen::Matrix3d> &
        {
            return camera_center_covariance_W_;
        }

        /// @brief Return optional camera-local small-angle attitude covariance.
        /// @return Read-only optional covariance reference.
        [[nodiscard]] auto
        attitudeCovarianceCamera() const noexcept -> const std::optional<Eigen::Matrix3d> &
        {
            return attitude_covariance_C_;
        }

      private:
        // PRIVATE METHODS
        [[nodiscard]] static auto
        validateRotation(const Eigen::Matrix3d &rotation_CW) -> Eigen::Matrix3d
        {
            // Validate both orthonormality and handedness so every stored matrix
            // has an unambiguous world-to-camera rotation interpretation.
            constexpr double tolerance = 1.0e-10;
            if (!rotation_CW.allFinite() ||
                (rotation_CW * rotation_CW.transpose() - Eigen::Matrix3d::Identity()).norm() >
                    tolerance ||
                std::abs(rotation_CW.determinant() - 1.0) > tolerance)
            {
                throw std::invalid_argument(
                    "CCameraView: R_CW must be a finite proper orthonormal rotation");
            }
            return rotation_CW;
        }

        [[nodiscard]] static auto
        validateCenter(const Eigen::Vector3d &camera_center_W) -> Eigen::Vector3d
        {
            if (!camera_center_W.allFinite())
            {
                throw std::invalid_argument("CCameraView: c_W must be finite");
            }
            return camera_center_W;
        }

        [[nodiscard]] static auto validateCovariance(std::optional<Eigen::Matrix3d> covariance)
            -> std::optional<Eigen::Matrix3d>
        {
            if (!covariance.has_value())
            {
                return std::nullopt;
            }
            return detail::validateCovariance(*covariance);
        }

        // PRIVATE DATA MEMBERS
        CFrameID frame_id_;
        CPinholeCameraCalibration calibration_;
        Eigen::Matrix3d rotation_CW_;
        Eigen::Vector3d camera_center_W_;
        std::optional<Eigen::Matrix3d> camera_center_covariance_W_;
        std::optional<Eigen::Matrix3d> attitude_covariance_C_;
    };

} // namespace slam_primitives
