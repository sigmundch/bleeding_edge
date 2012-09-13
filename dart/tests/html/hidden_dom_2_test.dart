#library('HiddenDom2Test');
#import('../../pkg/unittest/unittest.dart');
#import('../../pkg/unittest/html_config.dart');
#import('dart:html');

// Test that the dart:html API does not leak native jsdom methods:
//   appendChild operation.

main() {
  useHtmlConfiguration();

  test('test1', () {
    document.body.elements.add(new Element.html(@'''
<div id='div1'>
Hello World!
</div>'''));
    Element e = document.query('#div1');
    Element e2 = new Element.html(@"<div id='xx'>XX</div>");
    Expect.isTrue(e != null);

    checkNoSuchMethod(() { confuse(e).appendChild(e2); });

  });
}

class Decoy {
  void appendChild(x) { throw 'dead code'; }
}

confuse(x) => opaqueTrue() ? x : (opaqueTrue() ? new Object() : new Decoy());

/** Returns [:true:], but in a way that confuses the compiler. */
opaqueTrue() => true;  // Expand as needed.

checkNoSuchMethod(action()) {
  var ex = null;
  bool threw = false;
  try {
    action();
  } catch (e) {
    threw = true;
    ex = e;
  }
  if (!threw)
    Expect.fail('Action should have thrown exception');

  Expect.isTrue(ex is NoSuchMethodError, 'ex is NoSuchMethodError');
}
