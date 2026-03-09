#pragma once
#include <iomanip>
#include <iostream>
#include <limits>

#define RESET "\033[0m"
#define BLACK "\033[30m"   /* Black */
#define RED "\033[31m"     /* Red */
#define GREEN "\033[32m"   /* Green */
#define YELLOW "\033[33m"  /* Yellow */
#define BLUE "\033[34m"    /* Blue */
#define MAGENTA "\033[35m" /* Magenta */
#define CYAN "\033[36m"    /* Cyan */
#define WHITE "\033[37m"   /* White */

#define BOLD_BLACK "\033[1m\033[30m"   /* Bold Black */
#define BOLD_RED "\033[1m\033[31m"     /* Bold Red */
#define BOLD_GREEN "\033[1m\033[32m"   /* Bold Green */
#define BOLD_YELLOW "\033[1m\033[33m"  /* Bold Yellow */
#define BOLD_BLUE "\033[1m\033[34m"    /* Bold Blue */
#define BOLD_MAGENTA "\033[1m\033[35m" /* Bold Magenta */
#define BOLD_CYAN "\033[1m\033[36m"    /* Bold Cyan */
#define BOLD_WHITE "\033[1m\033[37m"   /* Bold White */

// Numerical limits and constants
using std::scientific;
const auto prec = std::setprecision(8);
const double EPS_DOUBLE = std::numeric_limits<double>::epsilon();