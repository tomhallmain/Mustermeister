require "test_helper"

class StringSimilarityTest < ActiveSupport::TestCase
  test "identical strings are fully similar" do
    assert_equal 1.0, StringSimilarity.ratio("Water plants", "Water plants")
  end

  test "ratio normalizes case and surrounding whitespace" do
    assert_equal 1.0, StringSimilarity.ratio("  Water Plants  ", "water plants")
  end

  test "a close typo is above the default threshold" do
    assert StringSimilarity.similar?("Water plants", "Water plants!")
  end

  test "clearly different strings are not similar" do
    assert_not StringSimilarity.similar?("Water plants", "File taxes")
    assert_equal 0.0, StringSimilarity.ratio("abc", "xyz")
  end

  test "a blank string against a non-blank string is never similar" do
    assert_equal 0.0, StringSimilarity.ratio("", "Water plants")
    assert_equal 0.0, StringSimilarity.ratio("Water plants", "")
  end

  test "two blank strings are trivially identical" do
    assert_equal 1.0, StringSimilarity.ratio("", "")
  end

  test "threshold boundary is inclusive" do
    ratio = StringSimilarity.ratio("Task 0", "Task 1")
    assert_in_delta 0.8333, ratio, 0.001

    assert StringSimilarity.similar?("Task 0", "Task 1", threshold: ratio)
    assert_not StringSimilarity.similar?("Task 0", "Task 1", threshold: ratio + 0.001)
  end

  test "similar? uses the default threshold when none is given" do
    assert_not StringSimilarity.similar?("Task 0", "Task 1")
    assert StringSimilarity.similar?("Buy groceries", "Buy groceries!")
  end
end
