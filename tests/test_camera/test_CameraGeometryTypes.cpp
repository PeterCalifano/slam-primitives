/// @file test_CameraGeometryTypes.cpp
/// @brief Verifies calibrated camera-view geometry and uncertainty invariants.

#include "slam-primitives/camera/CCameraView.h"
#include "slam-primitives/camera/CPinholeCameraCalibration.h"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

#include <Eigen/Core>
#include <Eigen/Geometry>

#include <limits>
#include <optional>
#include <stdexcept>
#include <type_traits>

using slam_primitives::CCameraView;
using slam_primitives::CFrameID;
using slam_primitives::CPinholeCameraCalibration;
using slam_primitives::SFeatureLocation2D;

namespace
{

    auto makeCalibrationMatrix() -> Eigen::Matrix3d
    {
        Eigen::Matrix3d intrinsic_matrix;
        intrinsic_matrix << 400.0, 5.0, 320.0, 0.0, 500.0, 240.0, 0.0, 0.0, 1.0;
        return intrinsic_matrix;
    }

} // namespace

static_assert(!std::is_default_constructible_v<CPinholeCameraCalibration>);
static_assert(!std::is_default_constructible_v<CCameraView>);

TEST_CASE("CPinholeCameraCalibration unprojects pixels with skew", "[types][camera]")
{
    const CPinholeCameraCalibration calibration{makeCalibrationMatrix()};
    const SFeatureLocation2D pixel{399.5, 190.0};
    const Eigen::Vector3d bearing = calibration.unproject(pixel);

    REQUIRE(calibration.matrix().isApprox(makeCalibrationMatrix(), 0.0));
    REQUIRE(bearing.x() == Catch::Approx(0.2));
    REQUIRE(bearing.y() == Catch::Approx(-0.1));
    REQUIRE(bearing.z() == Catch::Approx(1.0));
}

TEST_CASE("CPinholeCameraCalibration rejects invalid intrinsic matrices", "[types][camera]")
{
    Eigen::Matrix3d invalid_matrix = makeCalibrationMatrix();
    invalid_matrix(0, 0) = 0.0;
    REQUIRE_THROWS_AS(CPinholeCameraCalibration{invalid_matrix}, std::invalid_argument);

    invalid_matrix = makeCalibrationMatrix();
    invalid_matrix(2, 0) = 1.0e-3;
    REQUIRE_THROWS_AS(CPinholeCameraCalibration{invalid_matrix}, std::invalid_argument);

    invalid_matrix = makeCalibrationMatrix();
    invalid_matrix(1, 2) = std::numeric_limits<double>::infinity();
    REQUIRE_THROWS_AS(CPinholeCameraCalibration{invalid_matrix}, std::invalid_argument);
}

TEST_CASE("Large focal values do not relax pinhole matrix structure", "[types][camera]")
{
    Eigen::Matrix3d invalid_matrix = makeCalibrationMatrix();
    invalid_matrix(0, 0) = 1.0e20;
    invalid_matrix(2, 2) = 2.0;
    REQUIRE_THROWS_AS(CPinholeCameraCalibration{invalid_matrix}, std::invalid_argument);

    invalid_matrix = makeCalibrationMatrix();
    invalid_matrix(0, 0) = 1.0e20;
    invalid_matrix(2, 0) = 1.0e-3;
    REQUIRE_THROWS_AS(CPinholeCameraCalibration{invalid_matrix}, std::invalid_argument);

    Eigen::Matrix3d roundoff_matrix = makeCalibrationMatrix();
    roundoff_matrix(2, 0) = 1.0e-15;
    const CPinholeCameraCalibration calibration{roundoff_matrix};
    REQUIRE(calibration.matrix()(2, 0) == Catch::Approx(0.0));
}

TEST_CASE("CCameraView stores explicit world-to-camera geometry", "[types][camera]")
{
    const CPinholeCameraCalibration calibration{makeCalibrationMatrix()};
    const Eigen::Matrix3d rotation_CW =
        Eigen::AngleAxisd{0.25, Eigen::Vector3d::UnitY()}.toRotationMatrix();
    const Eigen::Vector3d camera_center_W{4.0, -2.0, 1.5};
    const Eigen::Matrix3d center_covariance_W =
        (Eigen::Vector3d{0.2, 0.3, 0.4}).array().square().matrix().asDiagonal();
    const Eigen::Matrix3d attitude_covariance_C =
        (Eigen::Vector3d{0.01, 0.02, 0.03}).array().square().matrix().asDiagonal();

    const CCameraView view{CFrameID{9U},    calibration,         rotation_CW,
                           camera_center_W, center_covariance_W, attitude_covariance_C};

    REQUIRE(view.getFrameID() == CFrameID{9U});
    REQUIRE(view.calibration().matrix().isApprox(calibration.matrix(), 0.0));
    REQUIRE(view.rotationCameraFromWorld().isApprox(rotation_CW, 1.0e-15));
    REQUIRE(view.cameraCenterWorld().isApprox(camera_center_W, 0.0));
    REQUIRE(view.cameraCenterCovarianceWorld().has_value());
    REQUIRE(view.cameraCenterCovarianceWorld()->isApprox(center_covariance_W, 0.0));
    REQUIRE(view.attitudeCovarianceCamera().has_value());
    REQUIRE(view.attitudeCovarianceCamera()->isApprox(attitude_covariance_C, 0.0));
}

TEST_CASE("CCameraView represents absent pose uncertainty explicitly", "[types][camera]")
{
    const CCameraView view{CFrameID{2U}, CPinholeCameraCalibration{makeCalibrationMatrix()},
                           Eigen::Matrix3d::Identity(), Eigen::Vector3d::Zero()};

    REQUIRE_FALSE(view.cameraCenterCovarianceWorld().has_value());
    REQUIRE_FALSE(view.attitudeCovarianceCamera().has_value());
}

TEST_CASE("CCameraView accepts large finite PSD pose covariance", "[types][camera]")
{
    const Eigen::Matrix3d large_covariance = 5.0e307 * Eigen::Matrix3d::Identity();
    const CCameraView view{CFrameID{2U}, CPinholeCameraCalibration{makeCalibrationMatrix()},
                           Eigen::Matrix3d::Identity(), Eigen::Vector3d::Zero(), large_covariance};

    REQUIRE(view.cameraCenterCovarianceWorld().has_value());
    REQUIRE((view.cameraCenterCovarianceWorld()->array() == large_covariance.array()).all());
}

TEST_CASE("CCameraView rejects a small negative variance beside a large one", "[types][camera]")
{
    Eigen::Matrix3d indefinite = Eigen::Matrix3d::Zero();
    indefinite.diagonal() << 1.0e20, 1.0, -1.0;
    REQUIRE_THROWS_AS(
        (CCameraView{CFrameID{1U}, CPinholeCameraCalibration{makeCalibrationMatrix()},
                     Eigen::Matrix3d::Identity(), Eigen::Vector3d::Zero(), indefinite}),
        std::invalid_argument);

    const Eigen::Matrix3d singular =
        Eigen::Vector3d{1.0, 2.0, 3.0} * Eigen::Vector3d{1.0, 2.0, 3.0}.transpose();
    REQUIRE_NOTHROW((CCameraView{CFrameID{1U}, CPinholeCameraCalibration{makeCalibrationMatrix()},
                                 Eigen::Matrix3d::Identity(), Eigen::Vector3d::Zero(), singular}));
}

TEST_CASE("CCameraView rejects invalid pose and covariance inputs", "[types][camera]")
{
    const CPinholeCameraCalibration calibration{makeCalibrationMatrix()};

    Eigen::Matrix3d invalid_rotation = Eigen::Matrix3d::Identity();
    invalid_rotation(0, 0) = 2.0;
    REQUIRE_THROWS_AS(
        (CCameraView{CFrameID{1U}, calibration, invalid_rotation, Eigen::Vector3d::Zero()}),
        std::invalid_argument);

    Eigen::Vector3d invalid_center = Eigen::Vector3d::Zero();
    invalid_center.x() = std::numeric_limits<double>::quiet_NaN();
    REQUIRE_THROWS_AS(
        (CCameraView{CFrameID{1U}, calibration, Eigen::Matrix3d::Identity(), invalid_center}),
        std::invalid_argument);

    Eigen::Matrix3d nonsymmetric_covariance = Eigen::Matrix3d::Identity();
    nonsymmetric_covariance(0, 1) = 0.25;
    REQUIRE_THROWS_AS((CCameraView{CFrameID{1U}, calibration, Eigen::Matrix3d::Identity(),
                                   Eigen::Vector3d::Zero(), nonsymmetric_covariance}),
                      std::invalid_argument);

    Eigen::Matrix3d indefinite_covariance = Eigen::Matrix3d::Identity();
    indefinite_covariance(2, 2) = -0.1;
    REQUIRE_THROWS_AS(
        (CCameraView{CFrameID{1U}, calibration, Eigen::Matrix3d::Identity(),
                     Eigen::Vector3d::Zero(), Eigen::Matrix3d::Identity(), indefinite_covariance}),
        std::invalid_argument);

    Eigen::Matrix3d overflow_scaled_covariance = 5.0e307 * Eigen::Matrix3d::Identity();
    overflow_scaled_covariance(0, 1) = 1.0e300;
    REQUIRE_THROWS_AS((CCameraView{CFrameID{1U}, calibration, Eigen::Matrix3d::Identity(),
                                   Eigen::Vector3d::Zero(), overflow_scaled_covariance}),
                      std::invalid_argument);
}
