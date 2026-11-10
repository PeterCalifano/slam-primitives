/// @file test_CCircularBuffer.cpp
/// @brief Check ring ordering, capacity, oldest removal and owned-value lifetimes.
#include <catch2/catch_test_macros.hpp>
#include "slam-primitives/containers/CCircularBuffer.h"

#include <deque>
#include <memory>
#include <stdexcept>
#include <utility>
#include <vector>

using namespace slam_primitives;

TEST_CASE("CCircularBuffer push below capacity", "[containers]")
{
    CCircularBuffer<int, 4> buf;
    buf.push_back(10);
    buf.push_back(20);

    REQUIRE(buf.size() == 2);
    REQUIRE_FALSE(buf.full());
    REQUIRE(buf[0] == 10);
    REQUIRE(buf[1] == 20);
    REQUIRE(buf.front() == 10);
    REQUIRE(buf.back() == 20);
}

TEST_CASE("CCircularBuffer push to capacity", "[containers]")
{
    CCircularBuffer<int, 3> buf;
    buf.push_back(1);
    buf.push_back(2);
    buf.push_back(3);

    REQUIRE(buf.size() == 3);
    REQUIRE(buf.full());
    REQUIRE(buf[0] == 1);
    REQUIRE(buf[1] == 2);
    REQUIRE(buf[2] == 3);
}

TEST_CASE("CCircularBuffer wrap-around overwrites oldest", "[containers]")
{
    CCircularBuffer<int, 3> buf;
    buf.push_back(1);
    buf.push_back(2);
    buf.push_back(3);
    buf.push_back(4); // overwrites 1

    REQUIRE(buf.size() == 3);
    REQUIRE(buf.full());
    REQUIRE(buf.front() == 2);
    REQUIRE(buf.back() == 4);
    REQUIRE(buf[0] == 2);
    REQUIRE(buf[1] == 3);
    REQUIRE(buf[2] == 4);
}

TEST_CASE("CCircularBuffer multiple wrap-arounds", "[containers]")
{
    CCircularBuffer<int, 2> buf;
    buf.push_back(1);
    buf.push_back(2);
    buf.push_back(3);
    buf.push_back(4);
    buf.push_back(5);

    REQUIRE(buf.size() == 2);
    REQUIRE(buf[0] == 4);
    REQUIRE(buf[1] == 5);
}

TEST_CASE("CCircularBuffer clear and re-push", "[containers]")
{
    CCircularBuffer<int, 3> buf;
    buf.push_back(1);
    buf.push_back(2);
    buf.push_back(3);
    buf.clear();

    REQUIRE(buf.size() == 0);
    REQUIRE(buf.empty());
    REQUIRE_FALSE(buf.full());

    buf.push_back(10);
    REQUIRE(buf.size() == 1);
    REQUIRE(buf.front() == 10);
    REQUIRE(buf.back() == 10);
}

TEST_CASE("CCircularBuffer range-for iteration", "[containers]")
{
    CCircularBuffer<int, 4> buf;
    buf.push_back(10);
    buf.push_back(20);
    buf.push_back(30);

    std::vector<int> values;
    for (auto val : buf)
    {
        values.push_back(val);
    }

    REQUIRE(values.size() == 3);
    REQUIRE(values[0] == 10);
    REQUIRE(values[1] == 20);
    REQUIRE(values[2] == 30);
}

TEST_CASE("CCircularBuffer range-for with wrap-around", "[containers]")
{
    CCircularBuffer<int, 3> buf;
    buf.push_back(1);
    buf.push_back(2);
    buf.push_back(3);
    buf.push_back(4);

    std::vector<int> values;
    for (auto val : buf)
    {
        values.push_back(val);
    }

    REQUIRE(values.size() == 3);
    REQUIRE(values[0] == 2);
    REQUIRE(values[1] == 3);
    REQUIRE(values[2] == 4);
}

TEST_CASE("CCircularBuffer empty buffer", "[containers]")
{
    CCircularBuffer<int, 4> buf;
    REQUIRE(buf.size() == 0);
    REQUIRE(buf.empty());
    REQUIRE_FALSE(buf.full());

    // Range-for on empty produces nothing
    int count = 0;
    for ([[maybe_unused]] auto val : buf)
    {
        ++count;
    }
    REQUIRE(count == 0);
}

TEST_CASE("CCircularBuffer single-element buffer N=1", "[containers]")
{
    CCircularBuffer<int, 1> buf;

    buf.push_back(42);
    REQUIRE(buf.size() == 1);
    REQUIRE(buf.full());
    REQUIRE(buf.front() == 42);
    REQUIRE(buf.back() == 42);
    REQUIRE(buf[0] == 42);

    buf.push_back(99);
    REQUIRE(buf.size() == 1);
    REQUIRE(buf[0] == 99);
    REQUIRE(buf.front() == 99);
}

TEST_CASE("CCircularBuffer capacity", "[containers]")
{
    CCircularBuffer<double, 8> buf;
    REQUIRE(CCircularBuffer<double, 8>::capacity() == 8);
}

TEST_CASE("CCircularBuffer oldest removal preserves wraparound and insertion", "[containers][window]")
{
    CCircularBuffer<int, 3> buffer;
    std::deque<int> expected;
    for (int value = 0; value < 100; ++value)
    {
        if (value % 3 == 0 && !expected.empty())
        {
            buffer.pop_front();
            expected.pop_front();
        }
        else
        {
            buffer.push_back(value);
            if (expected.size() == buffer.capacity())
            {
                expected.pop_front();
            }
            expected.push_back(value);
        }
        REQUIRE(buffer.size() == expected.size());
        REQUIRE(std::vector<int>(buffer.begin(), buffer.end()) == std::vector<int>(expected.begin(), expected.end()));
        if (!expected.empty())
        {
            REQUIRE(buffer.front() == expected.front());
            REQUIRE(buffer.back() == expected.back());
        }
    }
    while (!buffer.empty())
    {
        buffer.pop_front();
    }
    REQUIRE_THROWS_AS(buffer.pop_front(), std::out_of_range);
    REQUIRE(buffer.empty());
    buffer.push_back(101);
    REQUIRE(buffer.front() == 101);
    REQUIRE(buffer.back() == 101);
}

TEST_CASE("CCircularBuffer oldest removal supports capacity one", "[containers][window]")
{
    CCircularBuffer<int, 1> buffer;
    REQUIRE_THROWS_AS(buffer.pop_front(), std::out_of_range);
    for (int value = 1; value <= 3; ++value)
    {
        buffer.push_back(value);
        REQUIRE(buffer.front() == value);
        buffer.pop_front();
        REQUIRE(buffer.empty());
        REQUIRE_FALSE(buffer.full());
    }
}

TEST_CASE("CCircularBuffer oldest removal releases ownership", "[containers][window][lifetime]")
{
    CCircularBuffer<std::shared_ptr<int>, 2> buffer;
    auto first = std::make_shared<int>(1);
    auto second = std::make_shared<int>(2);
    const std::weak_ptr<int> first_observer = first;
    const std::weak_ptr<int> second_observer = second;
    buffer.push_back(std::move(first));
    buffer.push_back(std::move(second));
    buffer.pop_front();
    REQUIRE(first_observer.expired());
    REQUIRE_FALSE(second_observer.expired());
    REQUIRE(*buffer.front() == 2);
    buffer.pop_front();
    REQUIRE(second_observer.expired());

    CCircularBuffer<std::unique_ptr<int>, 2> move_only;
    move_only.push_back(std::make_unique<int>(7));
    move_only.pop_front();
    move_only.push_back(std::make_unique<int>(8));
    REQUIRE(*move_only.front() == 8);
}
