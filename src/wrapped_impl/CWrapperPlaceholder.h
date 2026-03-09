#pragma once

namespace cpp_playground
{
class CWrapperPlaceholder
{
  public:
    CWrapperPlaceholder() = default;

    double getDataMember() const;
    void setDataMember(double value);

    static double multiplyBy2(double value);

  private:
    double a_float_number_{0.0};
};

} // namespace cpp_playground
