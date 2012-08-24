// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * A class for holding onto the data for a date so that it can be built
 * up incrementally.
 */
class _DateBuilder {
  int year = 0,
      month = 0,
      day = 0,
      hour = 0,
      minute = 0,
      second = 0,
      fractionalSecond = 0;
  bool pm = false;
  bool utc = false;

  // Functions that exist just to be closurized so we can pass them to a general
  // method.
  void setYear(x) { year = x; }
  void setMonth(x) { month = x; }
  void setDay(x) { day = x; }
  void setHour(x) { hour = x; }
  void setMinute(x) { minute = x; }
  void setSecond(x) { second = x; }
  void setFractionalSecond(x) { fractionalSecond = x; }

  /**
   * Return a date built using our values. If no date portion is set,
   * use today's date, as otherwise the constructor will fail.
   */
  Date asDate() {
    if (year == 0 || month == 0 || day == 0) {
      var today = new Date.now();
      if (year == 0) year = today.year;
      if (month == 0) month = today.month;
      if (day == 0) day = today.day;
    }

    // TODO(alanknight): Validate the date, especially for things which
    // can crash the VM, e.g. large month values.
    return new Date(
        year,
        month,
        day,
        pm ? hour + 12 : hour,
        minute,
        second,
        fractionalSecond,
        utc);
  }
}

/**
 * A simple and not particularly general stream class to make parsing
 * dates from strings simpler. It is general enough to operate on either
 * lists or strings.
 */
class _Stream {
  var contents;
  int index = 0;

  _Stream(this.contents);

  bool atEnd() => index >= contents.length;

  Dynamic next() => contents[index++];

  /**
   * Return the next [howMany] items, or as many as there are remaining.
   * Advance the stream by that many positions.
   */
  read([howMany = 1]) {
    var result = peek(howMany);
    index += howMany;
    return result;
  }

  /**
   * Return the next [howMany] items, or as many as there are remaining.
   * Does not modify the stream position.
   */
  peek([howMany = 1]) {
    var result;
    if (contents is String) {
      result = contents.substring(
          index,
          min(index + howMany, contents.length));
    } else {
      // Assume List
      result = contents.getRange(index, howMany);
    }
    return result;
  }

  /** Return the remaining contents of the stream */
  rest() => peek(contents.length - index);

  /**
   * Find the index of the first element for which [f] returns true.
   * Advances the stream to that position.
   */
  int findIndex(Function f) {
    while (!atEnd()) {
      if (f(next())) return index - 1;
    }
    return null;
  }

  /**
   * Find the indexes of all the elements for which [f] returns true.
   * Leaves the stream positioned at the end.
   */
  List findIndexes(Function f) {
    var results = [];
    while (!atEnd()) {
      if (f(next())) results.add(index - 1);
    }
    return results;
  }

  /**
   * Assuming that the contents are characters, read as many digits as we
   * can see and then return the corresponding integer. Advance the stream.
   */
  var digitMatcher = const RegExp(@'\d+');
  int nextInteger() {
    var string = digitMatcher.stringMatch(rest());
    if (string == null || string.isEmpty()) return null;
    read(string.length);
    return parseInt(string);
  }
}
