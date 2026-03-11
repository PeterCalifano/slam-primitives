#include <catch2/catch_test_macros.hpp>
#include "slam_primitives/containers/CCircularBuffer.h"

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
