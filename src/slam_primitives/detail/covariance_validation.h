/// @file covariance_validation.h
/// @brief Validates small fixed-size covariance matrices without global scaling.

#pragma once
#include <Eigen/Core>
#include <Eigen/Eigenvalues>
#include <algorithm>
#include <cmath>
#include <limits>
#include <numeric>
#include <stdexcept>

namespace slam_primitives::detail
{

    /// @brief Validate and symmetrize a finite 2x2 or 3x3 PSD covariance.
    /// @tparam N Covariance dimension, either two or three.
    /// @param input Matrix to validate.
    /// @return Symmetric covariance with accepted roundoff averaged.
    /// @throws std::invalid_argument For nonfinite, asymmetric, or indefinite input.
    template <int N>
    [[nodiscard]] auto
    validateCovariance(const Eigen::Matrix<double, N, N> &input) -> Eigen::Matrix<double, N, N>
    {
        static_assert(N == 2 || N == 3);
        if (!input.allFinite())
        {
            throw std::invalid_argument("covariance must be finite");
        }

        Eigen::Matrix<double, N, N> symmetric = input;
        Eigen::Matrix<double, N, N> correlation = Eigen::Matrix<double, N, N>::Zero();
        constexpr double relative_tolerance = 128.0 * std::numeric_limits<double>::epsilon();
        for (int i = 0; i < N; ++i)
        {
            if (input(i, i) < 0.0)
            {
                throw std::invalid_argument("covariance must be positive semidefinite");
            }
            correlation(i, i) = input(i, i) > 0.0 ? 1.0 : 0.0;
        }

        for (int i = 0; i < N; ++i)
        {
            for (int j = i + 1; j < N; ++j)
            {
                const double a = input(i, j);
                const double b = input(j, i);
                const double denominator = std::sqrt(input(i, i)) * std::sqrt(input(j, j));
                const double local_scale = std::max({std::abs(a), std::abs(b), denominator});
                if (std::abs(a - b) > relative_tolerance * local_scale)
                {
                    throw std::invalid_argument("covariance must be symmetric");
                }
                const double value = std::midpoint(a, b);
                symmetric(i, j) = symmetric(j, i) = value;
                if (!(denominator > 0.0))
                {
                    if (std::abs(value) > 0.0)
                    {
                        throw std::invalid_argument("zero variance requires zero covariance");
                    }
                    continue;
                }
                const double rho = value / denominator;
                if (!std::isfinite(rho) || std::abs(rho) > 1.0 + relative_tolerance)
                {
                    throw std::invalid_argument("covariance must be positive semidefinite");
                }
                correlation(i, j) = correlation(j, i) = rho;
            }
        }

        const Eigen::SelfAdjointEigenSolver<Eigen::Matrix<double, N, N>> eigen_solver{
            correlation, Eigen::EigenvaluesOnly};
        if (eigen_solver.info() != Eigen::Success ||
            eigen_solver.eigenvalues().minCoeff() < -relative_tolerance * N)
        {
            throw std::invalid_argument("covariance must be positive semidefinite");
        }
        return symmetric;
    }

} // namespace slam_primitives::detail
