import 'dart:math';
import 'package:flutter/services.dart';
import 'formatter_type.dart';


class TextFieldFormatter implements TextInputFormatter {

  final FormatterType type;

  String? _formatter;
  List<String> _maskChars = [];
  Map<String, RegExp>? _maskFilter;

  int _maskLength = 0;
  final TextMatcher _resultTextArray = TextMatcher();
  String _resultTextMasked = "";

  TextEditingValue? _lastResValue;
  TextEditingValue? _lastNewValue;

TextFieldFormatter({
    String? format,
    Map<String, RegExp>? filter,
    String? initialText,
    this.type = FormatterType.lazy,
  }) {
    updateMask(mask: format, filter: filter ?? {"#": RegExp('[0-9]'), "A": RegExp('[^0-9]')});
    if (initialText != null) {
      formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: initialText));
    }
  }

  TextEditingValue updateMask({ String? mask, Map<String, RegExp>? filter}) {
    _formatter = mask;
    if (filter != null) {
      _updateFilter(filter);
    }
    _calcMaskLength();
    final unmaskedText = getUnmaskedText();
    clear();
    return formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: unmaskedText, selection: TextSelection.collapsed(offset: unmaskedText.length)));
  }



  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (_lastResValue == oldValue && newValue == _lastNewValue) {
      return oldValue;
    }
    if (oldValue.text.isEmpty) {
      _resultTextArray.clear();
    }
    _lastNewValue = newValue;
    return _lastResValue = _format(oldValue, newValue);
  }

  TextEditingValue _format(TextEditingValue oldValue, TextEditingValue newValue) {
    final mask = _formatter;

    if (mask == null || mask.isEmpty == true) {
      _resultTextMasked = newValue.text;
      _resultTextArray.set(newValue.text);
      return newValue;
    }

    final beforeText = oldValue.text;
    final afterText = newValue.text;

    final beforeSelection = oldValue.selection;
    final afterSelection = newValue.selection;

    final beforeSelectionStart = afterSelection.isValid ? beforeSelection.isValid ? beforeSelection.start : 0 : 0;
    final beforeSelectionLength = afterSelection.isValid ? beforeSelection.isValid ? beforeSelection.end - beforeSelection.start : 0 : oldValue.text.length;

    final lengthDifference = afterText.length - (beforeText.length - beforeSelectionLength);
    final lengthRemoved = lengthDifference < 0 ? lengthDifference.abs() : 0;
    final lengthAdded = lengthDifference > 0 ? lengthDifference : 0;

    final afterChangeStart = max(0, beforeSelectionStart - lengthRemoved);
    final afterChangeEnd = max(0, afterChangeStart + lengthAdded);

    final beforeReplaceStart = max(0, beforeSelectionStart - lengthRemoved);
    final beforeReplaceLength = beforeSelectionLength + lengthRemoved;

    final beforeResultTextLength = _resultTextArray.length;

    var currentResultTextLength = _resultTextArray.length;
    var currentResultSelectionStart = 0;
    var currentResultSelectionLength = 0;

    for (var i = 0; i < min(beforeReplaceStart + beforeReplaceLength, mask.length); i++) {
      if (_maskChars.contains(mask[i]) && currentResultTextLength > 0) {
        currentResultTextLength -= 1;
        if (i < beforeReplaceStart) {
          currentResultSelectionStart += 1;
        }
        if (i >= beforeReplaceStart) {
          currentResultSelectionLength += 1;
        }
      }
    }

    final replacementText = afterText.substring(afterChangeStart, afterChangeEnd);
    var targetCursorPosition = currentResultSelectionStart;
    if (replacementText.isEmpty) {
      _resultTextArray.removeRange(currentResultSelectionStart, currentResultSelectionStart + currentResultSelectionLength);
    } else {
      if (currentResultSelectionLength > 0) {
        _resultTextArray.removeRange(currentResultSelectionStart, currentResultSelectionStart + currentResultSelectionLength);
      }
      _resultTextArray.insert(currentResultSelectionStart, replacementText);
      targetCursorPosition += replacementText.length;
    }

    if (beforeResultTextLength == 0 && _resultTextArray.length  > 1) {
      for (var i = 0; i < mask.length; i++) {
        if (_maskChars.contains(mask[i])) {
          final resultPrefix = _resultTextArray._symbolArray.take(i).toList();
          for (var j = 0; j < resultPrefix.length; j++) {
            if (_resultTextArray.length <= j || (mask[j] != resultPrefix[j] || (mask[j] == resultPrefix[j] && j == resultPrefix.length - 1))) {
              _resultTextArray.removeRange(0, j);
              break;
            }
          }
          break;
        }
      }
    }

    var curTextPos = 0;
    var maskPos = 0;
    _resultTextMasked = "";
    var cursorPos = -1;
    var nonMaskedCount = 0;

    while (maskPos < mask.length) {
      final curMaskChar = mask[maskPos];
      final isMaskChar = _maskChars.contains(curMaskChar);

      var curTextInRange = curTextPos < _resultTextArray.length;

      String? curTextChar;
      if (isMaskChar && curTextInRange) {
        while (curTextChar == null && curTextInRange) {
          final potentialTextChar = _resultTextArray[curTextPos];
          if (_maskFilter?[curMaskChar]?.hasMatch(potentialTextChar) ?? false) {
            curTextChar = potentialTextChar;
          } else {
            _resultTextArray.removeAt(curTextPos);
            curTextInRange = curTextPos < _resultTextArray.length;
            if (curTextPos <= targetCursorPosition) {
              targetCursorPosition -= 1;
            }
          }
        }
      } else if (!isMaskChar && !curTextInRange && type == FormatterType.eager) {
        curTextInRange = true;
      }

      if (isMaskChar && curTextInRange && curTextChar != null) {
        _resultTextMasked += curTextChar;
        if (curTextPos == targetCursorPosition && cursorPos == -1) {
          cursorPos = maskPos - nonMaskedCount;
        }
        nonMaskedCount = 0;
        curTextPos += 1;
      } else {
        if (curTextPos == targetCursorPosition && cursorPos == -1 && !curTextInRange) {
          cursorPos = maskPos;
        }

        if (!curTextInRange) {
          break;
        } else {
          _resultTextMasked += mask[maskPos];
        }

        if (type == FormatterType.lazy || lengthRemoved > 0) {
          nonMaskedCount++;
        }
      }

      maskPos += 1;
    }

    if (nonMaskedCount > 0) {
      _resultTextMasked = _resultTextMasked.substring(0, _resultTextMasked.length - nonMaskedCount);
      cursorPos -= nonMaskedCount;
    }

    if (_resultTextArray.length > _maskLength) {
      _resultTextArray.removeRange(_maskLength, _resultTextArray.length);
    }

    final finalCursorPosition = cursorPos < 0 ? _resultTextMasked.length : cursorPos;

    return TextEditingValue(
        text: _resultTextMasked,
        selection: TextSelection(
            baseOffset: finalCursorPosition,
            extentOffset: finalCursorPosition,
            affinity: newValue.selection.affinity,
            isDirectional: newValue.selection.isDirectional
        )
    );
  }

  void _calcMaskLength() {
    _maskLength = 0;
    final mask = _formatter;
    if (mask != null) {
      for (var i = 0; i < mask.length; i++) {
        if (_maskChars.contains(mask[i])) {
          _maskLength++;
        }
      }
    }
  }

  void _updateFilter(Map<String, RegExp> filter) {
    _maskFilter = filter;
    _maskChars = _maskFilter?.keys.toList(growable: false) ?? [];
  }
  String? getMask() {
    return _formatter;
  }


  String getMaskedText() {
    return _resultTextMasked;
  }


  String getUnmaskedText() {
    return _resultTextArray.toString();
  }


  bool isFill() {
    return _resultTextArray.length == _maskLength;
  }

  void clear() {
    _resultTextMasked = "";
    _resultTextArray.clear();
    _lastResValue = null;
    _lastNewValue = null;
  }

  String maskText(String text) {
    return TextFieldFormatter(format: _formatter, filter: _maskFilter, initialText: text).getMaskedText();
  }


  String unmaskText(String text) {
    return TextFieldFormatter(format: _formatter, filter: _maskFilter, initialText: text).getUnmaskedText();
  }

}

class TextMatcher {

  final List<String> _symbolArray = <String>[];

  int get length => _symbolArray.fold(0, (prev, match) => prev + match.length);

  void removeRange(int start, int end) => _symbolArray.removeRange(start, end);

  void insert(int start, String substring) {
    for (var i = 0; i < substring.length; i++) {
      _symbolArray.insert(start + i, substring[i]);
    }
  }

  bool get isEmpty => _symbolArray.isEmpty;

  void removeAt(int index) => _symbolArray.removeAt(index);

  String operator[](int index) => _symbolArray[index];

  void clear() => _symbolArray.clear();

  @override
  String toString() => _symbolArray.join();

  void set(String text) {
    _symbolArray.clear();
    for (var i = 0; i < text.length; i++) {
      _symbolArray.add(text[i]);
    }
  }

}