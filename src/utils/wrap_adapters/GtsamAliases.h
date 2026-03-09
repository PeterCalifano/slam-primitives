#pragma once

#include <Eigen/Dense>

#if __has_include(<gtsam/base/Matrix.h>) && __has_include(<gtsam/base/Vector.h>)
#include <gtsam/base/Matrix.h>
#include <gtsam/base/Vector.h>
#else
namespace gtsam
{
    using Vector = Eigen::VectorXd;
    using Matrix = Eigen::MatrixXd;
} // namespace gtsam
#endif
