#pragma once
#include <array>
#include <cstdint>
#include <stdexcept>

namespace slam_primitives
{

    /// @brief Fixed-capacity circular (ring) buffer backed by std::array.
    ///
    /// When the buffer is full, push_back() overwrites the oldest element.
    /// Supports indexed access relative to the logical start, range-for
    /// iteration, and O(1) front/back access.
    ///
    /// @tparam T  Element type.
    /// @tparam N  Maximum number of elements (compile-time capacity).
    template <typename T, uint32_t N>
    class CCircularBuffer
    {
      public:
        CCircularBuffer() = default;

        // PUBLIC METHODS
        void push_back(const T &value)
        {
            data_[write_pos_] = value;
            advance();
        }

        void push_back(T &&value)
        {
            data_[write_pos_] = std::move(value);
            advance();
        }

        auto operator[](uint32_t index) const -> const T &
        {
            return data_[(start_ + index) % N];
        }

        auto operator[](uint32_t index) -> T &
        {
            return data_[(start_ + index) % N];
        }

        // O(1) access to front and back elements
        auto front() const -> const T & { return data_[start_]; }
        auto front() -> T & { return data_[start_]; }

        auto back() const -> const T &
        {
            uint32_t idx = (write_pos_ + N - 1) % N;
            return data_[idx];
        }

        auto back() -> T &
        {
            uint32_t idx = (write_pos_ + N - 1) % N;
            return data_[idx];
        }

        // Size and capacity queries
        auto size() const -> uint32_t { return size_; }
        static constexpr auto capacity() -> uint32_t { return N; }
        auto full() const -> bool { return size_ == N; }
        auto empty() const -> bool { return size_ == 0; }

        // Clear the buffer to an empty state
        void clear()
        {
            start_ = 0;
            write_pos_ = 0;
            size_ = 0;
        }

        // Iterator for range-for support
        class Iterator
        {
          public:
            using iterator_category = std::forward_iterator_tag;
            using value_type = T;
            using difference_type = std::ptrdiff_t;
            using pointer = const T *;
            using reference = const T &;

            Iterator(const CCircularBuffer *buf, uint32_t pos) : buf_(buf), pos_(pos) {}

            auto operator*() const -> reference { return (*buf_)[pos_]; }
            auto operator->() const -> pointer { return &(*buf_)[pos_]; }

            auto operator++() -> Iterator &
            {
                ++pos_;
                return *this;
            }

            auto operator++(int) -> Iterator
            {
                Iterator tmp = *this;
                ++pos_;
                return tmp;
            }

            auto operator==(const Iterator &other) const -> bool { return pos_ == other.pos_; }
            auto operator!=(const Iterator &other) const -> bool { return pos_ != other.pos_; }

          private:
            const CCircularBuffer *buf_;
            uint32_t pos_;
        };

        auto begin() const -> Iterator { return Iterator(this, 0); }
        auto end() const -> Iterator { return Iterator(this, size_); }

      private:
        // PRIVATE METHODS
        void advance()
        {
            if (size_ == N)
            {
                start_ = (start_ + 1) % N;
            }
            else
            {
                ++size_;
            }
            write_pos_ = (write_pos_ + 1) % N;
        }

        // PRIVATE DATA MEMBERS
        std::array<T, N> data_{};
        uint32_t start_{0};
        uint32_t write_pos_{0};
        uint32_t size_{0};
    };

} // namespace slam_primitives
