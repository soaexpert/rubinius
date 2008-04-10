require File.dirname(__FILE__) + '/../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#to_s" do

  before(:each) do
    @bigdec_str = "3.14159265358979323846264338327950288419716939937"
    @bigneg_str = "-3.1415926535897932384626433832795028841971693993"
    @bigdec = BigDecimal(@bigdec_str)
    @bigneg = BigDecimal(@bigneg_str)
  end

  it "return type is of class String" do
    @bigdec.to_s.kind_of?(String).should == true
    @bigneg.to_s.kind_of?(String).should == true
  end

  it "the default format looks like 0.xxxxEnn" do
    @bigdec.to_s.should  =~ /^0\.[0-9]*E[0-9]*$/
  end

  it "takes an optional argument" do
    lambda {@bigdec.to_s("F")}.should_not raise_error()
  end

  it "starts with + if + is supplied and value is positive" do
    @bigdec.to_s("+").should =~ /^\+.*/
    @bigneg.to_s("+").should_not =~ /^\+.*/
  end

  it "inserts a space every n chars, if integer n is supplied" do
    str =\
      "0.314 159 265 358 979 323 846 264 338 327 950 288 419 716 939 937E1"
    @bigdec.to_s(3).should == str
    str1 = '-123.45678 90123 45678 9'
    BigDecimal.new("-123.45678901234567890").to_s('5F').should ==  str1
  end

  it "can return a leading space for values > 0" do
    @bigdec.to_s(" F").should =~ /\ .*/
    @bigneg.to_s(" F").should_not =~ /\ .*/
  end

  it "can use engineering notation" do
    @bigdec.to_s("E").should =~ /^0\.[0-9]*E[0-9]*$/
  end

  it "can use conventional floating point notation" do
    @bigdec.to_s("F").should == @bigdec_str
    @bigneg.to_s("F").should == @bigneg_str
    str2 = "+123.45678901 23456789"
    BigDecimal.new('123.45678901234567890').to_s('+8F').should == str2
  end

end
