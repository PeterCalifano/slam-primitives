/// @file CCircularBuffer.h
/// @brief Fixed-capacity ring storage with insertion and oldest-value removal.
#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <stdexcept>
#include <utility>

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
    template <typename T, uint32_t N> class CCircularBuffer
    {
        static_assert(N > 0U, "CCircularBuffer requires positive capacity");

      public:
        /// @brief Construct empty storage with default-initialized slots.
        CCircularBuffer() = default;

        // PUBLIC METHODS
        /// @brief Copy a value to the newest slot, replacing the oldest when full.
        /// References to an overwritten slot and logical iterators are invalidated.
        void push_back(const T &value)
        {
            data_[write_pos_] = value;
            advance();
        }

        /// @brief Move a value to the newest slot, replacing the oldest when full.
        /// References to an overwritten slot and logical iterators are invalidated.
        void push_back(T &&value)
        {
            data_[write_pos_] = std::move(value);
            advance();
        }

        /// @brief Remove the oldest value while preserving the remaining order.
        /// Replaces its slot with T{} to release owned resources before advancing
        /// the logical front. Removed-value references and logical iterators are invalidated.
        /// Metadata updates are O(1); releasing the value depends on T's assignment.
        /// @throws std::out_of_range Without mutation when the buffer is empty.
        void pop_front()
        {
            if (empty())
            {
                throw std::out_of_range("CCircularBuffer: cannot remove from empty buffer");
            }
            data_[start_] = T{};
            start_ = (start_ + 1U) % N;
            --size_;
        }

        /// @brief View a value by logical index, where zero is the oldest.
        /// Requires index < size(); does not check the bound.
        auto operator[](uint32_t index) const -> const T &
        {
            return data_[(start_ + index) % N];
        }

        /// @brief Mutate a value by logical index; requires index < size().
        auto operator[](uint32_t index) -> T &
        {
            return data_[(start_ + index) % N];
        }

        // O(1) access to front and back elements
        /// @brief View the oldest value; requires a nonempty buffer.
        auto front() const -> const T &
        {
            return data_[start_];
        }
        /// @brief Mutate the oldest value; requires a nonempty buffer.
        auto front() -> T &
        {
            return data_[start_];
        }

        /// @brief View the newest value; requires a nonempty buffer.
        auto back() const -> const T &
        {
            uint32_t idx = (write_pos_ + N - 1) % N;
            return data_[idx];
        }

        /// @brief Mutate the newest value; requires a nonempty buffer.
        auto back() -> T &
        {
            uint32_t idx = (write_pos_ + N - 1) % N;
            return data_[idx];
        }

        // Size and capacity queries
        /// @brief Return the number of logically retained values.
        auto size() const -> uint32_t
        {
            return size_;
        }
        /// @brief Return the compile-time slot capacity.
        static constexpr auto capacity() -> uint32_t
        {
            return N;
        }
        /// @brief Return whether all slots are logically occupied.
        auto full() const -> bool
        {
            return size_ == N;
        }
        /// @brief Return whether no values are logically retained.
        auto empty() const -> bool
        {
            return size_ == 0;
        }

        /// @brief Clear logical contents and invalidate iterators and logical references.
        /// Slot values remain allocated until replaced or the buffer is destroyed.
        void clear()
        {
            start_ = 0;
            write_pos_ = 0;
            size_ = 0;
        }

        /// @brief Read-only iterator over logical order; compare within one buffer.
        class Iterator
        {
          public:
            using iterator_category = std::forward_iterator_tag;
            using value_type = T;
            using difference_type = std::ptrdiff_t;
            using pointer = const T *;
            using reference = const T &;

            /// @brief Bind a logical position to a buffer that outlives the iterator.
            Iterator(const CCircularBuffer *buf, uint32_t pos) : buf_(buf), pos_(pos) {}

            /// @brief View the current value; requires a position before end().
            auto operator*() const -> reference
            {
                return (*buf_)[pos_];
            }
            /// @brief Access the current value; requires a position before end().
            auto operator->() const -> pointer
            {
                return &(*buf_)[pos_];
            }

            /// @brief Advance to the next logical position.
            auto operator++() -> Iterator &
            {
                ++pos_;
                return *this;
            }

            /// @brief Advance and return the preceding logical position.
            auto operator++(int) -> Iterator
            {
                Iterator tmp = *this;
                ++pos_;
                return tmp;
            }

            /// @brief Compare logical positions within the same buffer.
            auto operator==(const Iterator &other) const -> bool
            {
                return pos_ == other.pos_;
            }
            /// @brief Compare unequal logical positions within the same buffer.
            auto operator!=(const Iterator &other) const -> bool
            {
                return pos_ != other.pos_;
            }

          private:
            const CCircularBuffer *buf_;
            uint32_t pos_;
        };

        /// @brief Return an iterator to the oldest logical value.
        auto begin() const -> Iterator
        {
            return Iterator(this, 0);
        }
        /// @brief Return the one-past-last logical iterator.
        auto end() const -> Iterator
        {
            return Iterator(this, size_);
        }

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
