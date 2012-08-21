#!/usr/bin/python
# Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""This module provides shared functionality for systems to generate
Dart APIs from the IDL database."""

import copy
import re

_pure_interfaces = set([
    # TODO(sra): DOMStringMap should be a class implementing Map<String,String>.
    'DOMStringMap',
    'ElementTimeControl',
    'ElementTraversal',
    'MediaQueryListListener',
    'NodeSelector',
    'SVGExternalResourcesRequired',
    'SVGFilterPrimitiveStandardAttributes',
    'SVGFitToViewBox',
    'SVGLangSpace',
    'SVGLocatable',
    'SVGStylable',
    'SVGTests',
    'SVGTransformable',
    'SVGURIReference',
    'SVGZoomAndPan',
    'TimeoutHandler'])

def IsPureInterface(interface_name):
  return interface_name in _pure_interfaces

#
# Renames for attributes that have names that are not legal Dart names.
#
_dart_attribute_renames = {
    'default': 'defaultValue',
    'final': 'finalValue',
}

#
# Interface version of the DOM needs to delegate typed array constructors to a
# factory provider.
#
interface_factories = {
    'Float32Array': '_TypedArrayFactoryProvider',
    'Float64Array': '_TypedArrayFactoryProvider',
    'Int8Array': '_TypedArrayFactoryProvider',
    'Int16Array': '_TypedArrayFactoryProvider',
    'Int32Array': '_TypedArrayFactoryProvider',
    'Uint8Array': '_TypedArrayFactoryProvider',
    'Uint16Array': '_TypedArrayFactoryProvider',
    'Uint32Array': '_TypedArrayFactoryProvider',
    'Uint8ClampedArray': '_TypedArrayFactoryProvider',
}

#
# Custom native specs for the dart2js dom.
#
_dart2js_dom_custom_native_specs = {
    # Decorate the singleton Console object, if present (workers do not have a
    # console).
    'Console': "=(typeof console == 'undefined' ? {} : console)",

    # DOMWindow aliased with global scope.
    'DOMWindow': '@*DOMWindow',
}

def IsRegisteredType(type_name):
  return type_name in _idl_type_registry

def ListImplementationInfo(interface, database):
  """Returns a tuple (elment_type, requires_indexer).
  If interface do not have to implement List, element_type is None.
  Otherwise element_type is list element type and requires_indexer
  is true iff this interface implementation must have indexer and
  false otherwise.  False means that interface implementation
  inherits indexer and may just reuse it."""
  element_type = MaybeListElementType(interface)
  if element_type:
    return (element_type, True)

  for parent in interface.parents:
    if database.HasInterface(parent.type.id):
      parent_interface = database.GetInterface(parent.type.id)
      (element_type, _) = ListImplementationInfo(parent_interface, database)
      if element_type:
        return (element_type, False)

  return (None, None)


def MaybeListElementTypeName(type_name):
  """Returns the List element type T from string of form "List<T>", or None."""
  match = re.match(r'sequence<(\w*)>$', type_name)
  if match:
    return match.group(1)
  return None

def MaybeListElementType(interface):
  """Returns the List element type T, or None in interface does not implement
  List<T>.
  """
  for parent in interface.parents:
    element_type = MaybeListElementTypeName(parent.type.id)
    if element_type:
      return element_type
  return None

def MaybeTypedArrayElementType(interface):
  """Returns the typed array element type, or None in interface is not a
  TypedArray.
  """
  # Typed arrays implement ArrayBufferView and List<T>.
  for parent in interface.parents:
    if parent.type.id == 'ArrayBufferView':
      return MaybeListElementType(interface)
  return None

def MaybeTypedArrayElementTypeInHierarchy(interface, database):
  """Returns the typed array element type, or None in interface is not a
  TypedArray.  Checks the whole parent hierarchy.
  """
  element_type = MaybeTypedArrayElementType(interface)
  if element_type:
    return element_type
  for parent in interface.parents:
    if database.HasInterface(parent.type.id):
      parent_interface = database.GetInterface(parent.type.id)
      element_type = MaybeTypedArrayElementType(parent_interface)
      if element_type:
        return element_type

  return None

def MakeNativeSpec(javascript_binding_name):
  if javascript_binding_name in _dart2js_dom_custom_native_specs:
    return _dart2js_dom_custom_native_specs[javascript_binding_name]
  else:
    # Make the class 'hidden' so it is dynamically patched at runtime.  This
    # is useful not only for browser compat, but to allow code that links
    # against dart:dom_deprecated to load in a worker isolate.
    return '*' + javascript_binding_name


def MatchSourceFilter(thing):
  return 'WebKit' in thing.annotations or 'Dart' in thing.annotations


def DartType(idl_type_name):
  if idl_type_name in _idl_type_registry:
    return _idl_type_registry[idl_type_name].dart_type or idl_type_name
  return idl_type_name


class ParamInfo(object):
  """Holder for various information about a parameter of a Dart operation.

  Attributes:
    name: Name of parameter.
    type_id: Original type id.  None for merged types.
    dart_type: DartType of parameter.
    is_optional: Parameter optionality.
  """
  def __init__(self, name, type_id, dart_type, is_optional):
    self.name = name
    self.type_id = type_id
    self.dart_type = dart_type
    self.is_optional = is_optional

  def __repr__(self):
    content = 'name = %s, type_id = %s, dart_type = %s, is_optional = %s' % (
        self.name, self.type_id, self.dart_type, self.is_optional)
    return '<ParamInfo(%s)>' % content


# Given a list of overloaded arguments, render a dart argument.
def _DartArg(args, interface, constructor=False):
  # Given a list of overloaded arguments, choose a suitable name.
  def OverloadedName(args):
    return '_OR_'.join(sorted(set(arg.id for arg in args)))

  # Given a list of overloaded arguments, choose a suitable type.
  def OverloadedType(args):
    type_ids = sorted(set(arg.type.id for arg in args))
    dart_types = sorted(set(DartType(arg.type.id) for arg in args))
    if len(dart_types) == 1:
      if len(type_ids) == 1:
        return (type_ids[0], type_ids[0])
      else:
        return (None, type_ids[0])
    else:
      return (None, TypeName(type_ids, interface))

  def IsOptional(argument):
    if not argument:
      return True
    if 'Callback' in argument.ext_attrs:
      # Callbacks with 'Optional=XXX' are treated as optional arguments.
      return 'Optional' in argument.ext_attrs
    if constructor:
      # FIXME: Constructors with 'Optional=XXX' shouldn't be treated as
      # optional arguments.
      return 'Optional' in argument.ext_attrs
    return False

  filtered = filter(None, args)
  is_optional = any(IsOptional(arg) for arg in args)
  (type_id, dart_type) = OverloadedType(filtered)
  name = OverloadedName(filtered)
  return ParamInfo(name, type_id, dart_type, is_optional)

def IsOptional(argument):
  return ('Optional' in argument.ext_attrs and
          argument.ext_attrs['Optional'] == None)

def AnalyzeOperation(interface, operations):
  """Makes operation calling convention decision for a set of overloads.

  Returns: An OperationInfo object.
  """

  # split operations with optional args into multiple operations
  split_operations = []
  for operation in operations:
    for i in range(0, len(operation.arguments)):
      if IsOptional(operation.arguments[i]):
        new_operation = copy.deepcopy(operation)
        new_operation.arguments = new_operation.arguments[:i]
        split_operations.append(new_operation)
    split_operations.append(operation)

  # Zip together arguments from each overload by position, then convert
  # to a dart argument.
  args = map(lambda *args: _DartArg(args, interface),
             *(op.arguments for op in split_operations))

  info = OperationInfo()
  info.operations = operations
  info.overloads = split_operations
  info.declared_name = operations[0].id
  info.name = operations[0].ext_attrs.get('DartName', info.declared_name)
  info.constructor_name = None
  info.js_name = info.declared_name
  info.type_name = operations[0].type.id   # TODO: widen.
  info.param_infos = args
  return info


def AnalyzeConstructor(interface):
  """Returns an OperationInfo object for the constructor.

  Returns None if the interface has no Constructor.
  """
  def GetArgs(func_value):
    return map(lambda arg: _DartArg([arg], interface, True),
               func_value.arguments)

  if 'Constructor' in interface.ext_attrs:
    name = None
    func_value = interface.ext_attrs.get('Constructor')
    if func_value:
      # [Constructor(param,...)]
      args = GetArgs(func_value)
      idl_args = func_value.arguments
    else: # [Constructor]
      args = []
      idl_args = []
  else:
    func_value = interface.ext_attrs.get('NamedConstructor')
    if func_value:
      name = func_value.id
      args = GetArgs(func_value)
      idl_args = func_value.arguments
    else:
      return None

  info = OperationInfo()
  info.overloads = None
  info.idl_args = idl_args
  info.declared_name = name
  info.name = name
  info.constructor_name = None
  info.js_name = name
  info.type_name = interface.id
  info.param_infos = args
  return info

def IsDartListType(type):
  return type == 'List' or type.startswith('sequence<')

def IsDartCollectionType(type):
  return IsDartListType(type)

def FindMatchingAttribute(interface, attr1):
  matches = [attr2 for attr2 in interface.attributes
             if attr1.id == attr2.id]
  if matches:
    assert len(matches) == 1
    return matches[0]
  return None


def DartDomNameOfAttribute(attr):
  """Returns the Dart name for an IDLAttribute.

  attr.id is the 'native' or JavaScript name.

  To ensure uniformity, work with the true IDL name until as late a possible,
  e.g. translate to the Dart name when generating Dart code.
  """
  name = attr.id
  name = _dart_attribute_renames.get(name, name)
  name = attr.ext_attrs.get('DartName', None) or name
  return name


def TypeOrNothing(dart_type, comment=None):
  """Returns string for declaring something with |dart_type| in a context
  where a type may be omitted.
  The string is empty or has a trailing space.
  """
  if dart_type == 'Dynamic':
    if comment:
      return '/*%s*/ ' % comment   # Just a comment foo(/*T*/ x)
    else:
      return ''                    # foo(x) looks nicer than foo(Dynamic x)
  else:
    return dart_type + ' '


def TypeOrVar(dart_type, comment=None):
  """Returns string for declaring something with |dart_type| in a context
  where if a type is omitted, 'var' must be used instead."""
  if dart_type == 'Dynamic':
    if comment:
      return 'var /*%s*/' % comment   # e.g.  var /*T*/ x;
    else:
      return 'var'                    # e.g.  var x;
  else:
    return dart_type


class OperationInfo(object):
  """Holder for various derived information from a set of overloaded operations.

  Attributes:
    overloads: A list of IDL operation overloads with the same name.
    name: A string, the simple name of the operation.
    constructor_name: A string, the name of the constructor iff the constructor
       is named, e.g. 'fromList' in  Int8Array.fromList(list).
    type_name: A string, the name of the return type of the operation.
    param_infos: A list of ParamInfo.
  """

  def ParametersInterfaceDeclaration(self, rename_type):
    """Returns a formatted string declaring the parameters for the interface."""
    return self._FormatParams(
        self.param_infos, None,
        lambda param: TypeOrNothing(rename_type(param.dart_type), param.type_id))

  def ParametersImplementationDeclaration(
      self, rename_type, default_value='null'):
    """Returns a formatted string declaring the parameters for the
    implementation.

    Args:
      rename_type: A function that allows the types to be renamed.
        The function is applied to the parameter's dart_type.
    """
    return self._FormatParams(
        self.param_infos, default_value,
        lambda param: TypeOrNothing(rename_type(param.dart_type)))

  def ParametersAsArgumentList(self):
    """Returns a string of the parameter names suitable for passing the
    parameters as arguments.
    """
    return ', '.join(map(lambda param_info: param_info.name, self.param_infos))

  def _FormatParams(self, params, default_value, type_fn):
    def FormatParam(param):
      """Returns a parameter declaration fragment for an ParamInfo."""
      type = type_fn(param)
      if param.is_optional and default_value and default_value != 'null':
        return '%s%s = %s' % (type, param.name, default_value)
      return '%s%s' % (type, param.name)

    required = []
    optional = []
    for param_info in params:
      if param_info.is_optional:
        optional.append(param_info)
      else:
        if optional:
          raise Exception('Optional parameters cannot precede required ones: '
                          + str(params))
        required.append(param_info)
    argtexts = map(FormatParam, required)
    if optional:
      argtexts.append('[' + ', '.join(map(FormatParam, optional)) + ']')
    return ', '.join(argtexts)

  def IsStatic(self):
    is_static = self.overloads[0].is_static
    assert any([is_static == o.is_static for o in self.overloads])
    return is_static

  def ConstructorFullName(self):
    if self.constructor_name:
      return self.type_name + '.' + self.constructor_name
    else:
      return self.type_name


def ConstantOutputOrder(a, b):
  """Canonical output ordering for constants."""
  if a.id < b.id: return -1
  if a.id > b.id: return 1
  return 0


def _FormatNameList(names):
  """Returns JavaScript array literal expression with one name per line."""
  #names = sorted(names)
  if len(names) <= 1:
    expression_string = str(names)  # e.g.  ['length']
  else:
    expression_string = ',\n   '.join(str(names).split(','))
    expression_string = expression_string.replace('[', '[\n    ')
  return expression_string


def IndentText(text, indent):
  """Format lines of text with indent."""
  def FormatLine(line):
    if line.strip():
      return '%s%s\n' % (indent, line)
    else:
      return '\n'
  return ''.join(FormatLine(line) for line in text.split('\n'))

# Given a sorted sequence of type identifiers, return an appropriate type
# name
def TypeName(type_ids, interface):
  # Dynamically type this field for now.
  return 'Dynamic'

# ------------------------------------------------------------------------------

class IDLTypeInfo(object):
  def __init__(self, idl_type, data):
    self._idl_type = idl_type
    self._data = data

  def idl_type(self):
    return self._idl_type

  def dart_type(self):
    return self._data.dart_type or self._idl_type

  def native_type(self):
    return self._data.native_type or self._idl_type

  def requires_v8_scope(self):
    return self._data.requires_v8_scope

  def emit_to_native(self, emitter, idl_node, accept_null, name, handle):
    if 'Callback' in idl_node.ext_attrs:
      function_name = 'create'
      if accept_null:
        function_name += 'WithNullCheck'
      emitter.Emit(
        '\n'
        '        RefPtr<$TYPE> $NAME = Dart$IDL_TYPE::$FUNCTION_NAME($HANDLE, exception);\n'
        '        if (exception)\n'
        '            goto fail;\n',
        TYPE=self.native_type(),
        NAME=name,
        FUNCTION_NAME=function_name,
        IDL_TYPE=self.idl_type(),
        HANDLE=handle)
      return

    if self.custom_to_native():
      type = 'RefPtr<%s>' % self.native_type()
    else:
      type = '%s*' % self.native_type()
    emitter.Emit(
        '\n'
        '        $TYPE $NAME = Dart$IDL_TYPE::toNative($HANDLE, exception);\n'
        '        if (exception)\n'
        '            goto fail;\n',
        TYPE=type,
        NAME=name,
        IDL_TYPE=self.idl_type(),
        HANDLE=handle)

  def argument_expression(self, name, interface_name):
    return '%s.get()' % name if self.custom_to_native() else name

  def custom_to_native(self):
    return self._data.custom_to_native

  def parameter_type(self):
    return '%s*' % self.native_type()

  def webcore_includes(self):
    WTF_INCLUDES = [
        'ArrayBuffer',
        'ArrayBufferView',
        'Float32Array',
        'Float64Array',
        'Int8Array',
        'Int16Array',
        'Int32Array',
        'Uint8Array',
        'Uint16Array',
        'Uint32Array',
        'Uint8ClampedArray',
    ]

    if self._idl_type in WTF_INCLUDES:
      return ['<wtf/%s.h>' % self.native_type()]

    if not self._idl_type.startswith('SVG'):
      return ['"%s.h"' % self.native_type()]

    if self._idl_type in ['SVGNumber', 'SVGPoint']:
      return ['"SVGPropertyTearOff.h"']
    if self._idl_type.startswith('SVGPathSeg'):
      include = self._idl_type.replace('Abs', '').replace('Rel', '')
    else:
      include = self._idl_type
    return ['"%s.h"' % include] + _svg_supplemental_includes

  def receiver(self):
    return 'receiver->'

  def conversion_includes(self):
    includes = [self._idl_type] + (self._data.conversion_includes or [])
    return ['"Dart%s.h"' % include for include in includes]

  def to_native_includes(self):
    return ['"Dart%s.h"' % self.idl_type()]

  def to_dart_conversion(self, value, interface_name=None, attributes=None):
    return 'Dart%s::toDart(%s)' % (self._idl_type, value)

  def custom_to_dart(self):
    return self._data.custom_to_dart


class InterfaceIDLTypeInfo(IDLTypeInfo):
  def __init__(self, idl_type, data):
    super(InterfaceIDLTypeInfo, self).__init__(idl_type, data)


class SequenceIDLTypeInfo(IDLTypeInfo):
  def __init__(self, idl_type, data, item_info):
    super(SequenceIDLTypeInfo, self).__init__(idl_type, data)
    self._item_info = item_info

  def dart_type(self):
    return 'List<%s>' % self._item_info.dart_type()

  def to_dart_conversion(self, value, interface_name=None, attributes=None):
    return 'DartDOMWrapper::vectorToDart<Dart%s>(%s)' % (self._item_info.native_type(), value)

  def conversion_includes(self):
    return self._item_info.conversion_includes()


class DOMStringArrayTypeInfo(SequenceIDLTypeInfo):
  def __init__(self, data, item_info):
    super(DOMStringArrayTypeInfo, self).__init__('DOMString[]', data, item_info)

  def emit_to_native(self, emitter, idl_node, accept_null, name, handle):
    assert not accept_null
    emitter.Emit(
        '\n'
        '        RefPtr<DOMStringList> $NAME = DartDOMStringList::toNative($HANDLE, exception);\n'
        '        if (exception)\n'
        '            goto fail;\n',
        NAME=name,
        HANDLE=handle)

  def to_native_includes(self):
    return ['"DartDOMStringList.h"']


class PrimitiveIDLTypeInfo(IDLTypeInfo):
  def __init__(self, idl_type, data):
    super(PrimitiveIDLTypeInfo, self).__init__(idl_type, data)

  def emit_to_native(self, emitter, idl_node, accept_null, name, handle):
    function_name = 'dartTo%s' % self._capitalized_native_type()
    if accept_null:
      function_name += 'WithNullCheck'
    type = self.native_type()
    if type == 'SerializedScriptValue':
      type = 'RefPtr<%s>' % type
    if type == 'String':
      type = 'DartStringAdapter'
    emitter.Emit(
        '\n'
        '        $TYPE $NAME = DartUtilities::$FUNCTION_NAME($HANDLE, exception);\n'
        '        if (exception)\n'
        '            goto fail;\n',
        TYPE=type,
        NAME=name,
        FUNCTION_NAME=function_name,
        HANDLE=handle)

  def parameter_type(self):
    if self.native_type() == 'String':
      return 'const String&'
    return self.native_type()

  def conversion_includes(self):
    return []

  def to_native_includes(sefl):
    return []

  def to_dart_conversion(self, value, interface_name=None, attributes=None):
    function_name = self._capitalized_native_type()
    function_name = function_name[0].lower() + function_name[1:]
    function_name = 'DartUtilities::%sToDart' % function_name
    if attributes and 'TreatReturnedNullStringAs' in attributes:
      function_name += 'WithNullCheck'
    return '%s(%s)' % (function_name, value)

  def webcore_getter_name(self):
    return self._data.webcore_getter_name

  def webcore_setter_name(self):
    return self._data.webcore_setter_name

  def _capitalized_native_type(self):
    return re.sub(r'(^| )([a-z])', lambda x: x.group(2).upper(), self.native_type())


class SVGTearOffIDLTypeInfo(IDLTypeInfo):
  def __init__(self, idl_type, data):
    super(SVGTearOffIDLTypeInfo, self).__init__(idl_type, data)

  def native_type(self):
    if self._data.native_type:
      return self._data.native_type
    tear_off_type = 'SVGPropertyTearOff'
    if self._idl_type.endswith('List'):
      tear_off_type = 'SVGListPropertyTearOff'
    return '%s<%s>' % (tear_off_type, self._idl_type)

  def receiver(self):
    if self._idl_type.endswith('List'):
      return 'receiver->'
    return 'receiver->propertyReference().'

  def to_dart_conversion(self, value, interface_name, attributes):
    svg_primitive_types = ['SVGAngle', 'SVGLength', 'SVGMatrix',
        'SVGNumber', 'SVGPoint', 'SVGRect', 'SVGTransform']
    conversion_cast = '%s::create(%s)'
    if interface_name.startswith('SVGAnimated'):
      conversion_cast = 'static_cast<%s*>(%s)'
    elif self.idl_type() == 'SVGStringList':
      conversion_cast = '%s::create(receiver, %s)'
    elif interface_name.endswith('List'):
      conversion_cast = 'static_cast<%s*>(%s.get())'
    elif self.idl_type() in svg_primitive_types:
      conversion_cast = '%s::create(%s)'
    else:
      conversion_cast = 'static_cast<%s*>(%s)'
    conversion_cast = conversion_cast % (self.native_type(), value)
    return 'Dart%s::toDart(%s)' % (self._idl_type, conversion_cast)

  def argument_expression(self, name, interface_name):
    return name if interface_name.endswith('List') else '%s->propertyReference()' % name


class TypeData(object):
  def __init__(self, clazz, dart_type=None, native_type=None,
               custom_to_dart=None, custom_to_native=None,
               conversion_includes=None,
               webcore_getter_name='getAttribute',
               webcore_setter_name='setAttribute',
               requires_v8_scope=False):
    self.clazz = clazz
    self.dart_type = dart_type
    self.native_type = native_type
    self.custom_to_dart = custom_to_dart
    self.custom_to_native = custom_to_native
    self.conversion_includes = conversion_includes
    self.webcore_getter_name = webcore_getter_name
    self.webcore_setter_name = webcore_setter_name
    self.requires_v8_scope = requires_v8_scope


_idl_type_registry = {
    'boolean': TypeData(clazz='Primitive', dart_type='bool', native_type='bool',
                        webcore_getter_name='hasAttribute',
                        webcore_setter_name='setBooleanAttribute'),
    'byte': TypeData(clazz='Primitive', dart_type='int', native_type='int'),
    'octet': TypeData(clazz='Primitive', dart_type='int', native_type='int'),
    'short': TypeData(clazz='Primitive', dart_type='int', native_type='int'),
    'unsigned short': TypeData(clazz='Primitive', dart_type='int',
        native_type='int'),
    'int': TypeData(clazz='Primitive', dart_type='int'),
    'unsigned int': TypeData(clazz='Primitive', dart_type='int',
        native_type='unsigned'),
    'long': TypeData(clazz='Primitive', dart_type='int', native_type='int',
        webcore_getter_name='getIntegralAttribute',
        webcore_setter_name='setIntegralAttribute'),
    'unsigned long': TypeData(clazz='Primitive', dart_type='int',
                              native_type='unsigned',
                              webcore_getter_name='getUnsignedIntegralAttribute',
                              webcore_setter_name='setUnsignedIntegralAttribute'),
    'long long': TypeData(clazz='Primitive', dart_type='int'),
    'unsigned long long': TypeData(clazz='Primitive', dart_type='int'),
    'float': TypeData(clazz='Primitive', dart_type='num', native_type='double'),
    'double': TypeData(clazz='Primitive', dart_type='num'),

    'any': TypeData(clazz='Primitive', dart_type='Object'),
    'Array': TypeData(clazz='Primitive', dart_type='List'),
    'custom': TypeData(clazz='Primitive', dart_type='Dynamic'),
    'Date': TypeData(clazz='Primitive', dart_type='Date', native_type='double'),
    'DOMObject': TypeData(clazz='Primitive', dart_type='Object', native_type='ScriptValue'),
    'DOMString': TypeData(clazz='Primitive', dart_type='String', native_type='String'),
    # TODO(vsm): This won't actually work until we convert the Map to
    # a native JS Map for JS DOM.
    'Dictionary': TypeData(clazz='Primitive', dart_type='Map', requires_v8_scope=True),
    # TODO(sra): Flags is really a dictionary: {create:bool, exclusive:bool}
    # http://dev.w3.org/2009/dap/file-system/file-dir-sys.html#the-flags-interface
    'Flags': TypeData(clazz='Primitive', dart_type='Object'),
    'DOMTimeStamp': TypeData(clazz='Primitive', dart_type='int', native_type='unsigned long long'),
    'object': TypeData(clazz='Primitive', dart_type='Object', native_type='ScriptValue'),
    'PositionOptions': TypeData(clazz='Primitive', dart_type='Object'),
    # TODO(sra): Come up with some meaningful name so that where this appears in
    # the documentation, the user is made aware that only a limited subset of
    # serializable types are actually permitted.
    'SerializedScriptValue': TypeData(clazz='Primitive', dart_type='Dynamic'),
    # TODO(sra): Flags is really a dictionary: {create:bool, exclusive:bool}
    # http://dev.w3.org/2009/dap/file-system/file-dir-sys.html#the-flags-interface
    'WebKitFlags': TypeData(clazz='Primitive', dart_type='Object'),

    'sequence': TypeData(clazz='Primitive', dart_type='List'),
    'void': TypeData(clazz='Primitive', dart_type='void'),

    'CSSRule': TypeData(clazz='Interface', conversion_includes=['CSSImportRule']),
    'DOMException': TypeData(clazz='Interface', native_type='DOMCoreException'),
    'DOMStringList': TypeData(clazz='Interface', dart_type='List<String>', custom_to_native=True),
    'DOMStringMap': TypeData(clazz='Interface', dart_type='Map<String, String>'),
    'DOMWindow': TypeData(clazz='Interface', custom_to_dart=True),
    'Element': TypeData(clazz='Interface', custom_to_dart=True),
    'EventListener': TypeData(clazz='Interface', custom_to_native=True),
    'EventTarget': TypeData(clazz='Interface', custom_to_native=True),
    'HTMLElement': TypeData(clazz='Interface', custom_to_dart=True),
    'IDBAny': TypeData(clazz='Interface', dart_type='Dynamic', custom_to_native=True),
    'IDBKey': TypeData(clazz='Interface', dart_type='Dynamic', custom_to_native=True),
    'MutationRecordArray': TypeData(clazz='Interface',  # C++ pass by pointer.
                                    native_type='MutationRecordArray',
                                    dart_type='List<MutationRecord>'),
    'StyleSheet': TypeData(clazz='Interface', conversion_includes=['CSSStyleSheet']),
    'SVGElement': TypeData(clazz='Interface', custom_to_dart=True),

    'SVGAngle': TypeData(clazz='SVGTearOff'),
    'SVGLength': TypeData(clazz='SVGTearOff'),
    'SVGLengthList': TypeData(clazz='SVGTearOff'),
    'SVGMatrix': TypeData(clazz='SVGTearOff'),
    'SVGNumber': TypeData(clazz='SVGTearOff', native_type='SVGPropertyTearOff<float>'),
    'SVGNumberList': TypeData(clazz='SVGTearOff'),
    'SVGPathSegList': TypeData(clazz='SVGTearOff', native_type='SVGPathSegListPropertyTearOff'),
    'SVGPoint': TypeData(clazz='SVGTearOff', native_type='SVGPropertyTearOff<FloatPoint>'),
    'SVGPointList': TypeData(clazz='SVGTearOff'),
    'SVGPreserveAspectRatio': TypeData(clazz='SVGTearOff'),
    'SVGRect': TypeData(clazz='SVGTearOff', native_type='SVGPropertyTearOff<FloatRect>'),
    'SVGStringList': TypeData(clazz='SVGTearOff', native_type='SVGStaticListPropertyTearOff<SVGStringList>'),
    'SVGTransform': TypeData(clazz='SVGTearOff'),
    'SVGTransformList': TypeData(clazz='SVGTearOff', native_type='SVGTransformListPropertyTearOff'),
}

_svg_supplemental_includes = [
    '"SVGAnimatedPropertyTearOff.h"',
    '"SVGAnimatedListPropertyTearOff.h"',
    '"SVGStaticListPropertyTearOff.h"',
    '"SVGAnimatedListPropertyTearOff.h"',
    '"SVGTransformListPropertyTearOff.h"',
    '"SVGPathSegListPropertyTearOff.h"',
]

class TypeRegistry(object):
  def __init__(self, database, renamer=None):
    self._database = database
    self._renamer = renamer
    self._cache = {}

  def TypeInfo(self, type_name):
    if not type_name in self._cache:
      self._cache[type_name] = self._TypeInfo(type_name)
    return self._cache[type_name]

  def DartType(self, type_name):
    dart_type = self.TypeInfo(type_name).dart_type()
    if self._database.HasInterface(dart_type):
      interface = self._database.GetInterface(dart_type)
      if self._renamer:
        return self._renamer.RenameInterface(interface)
      else:
        return interface.id
    return dart_type

  def _TypeInfo(self, type_name):
    match = re.match(r'(?:sequence<(\w+)>|(\w+)\[\])$', type_name)
    if match:
      if type_name == 'DOMString[]':
        return DOMStringArrayTypeInfo(TypeData('Sequence'), self.TypeInfo('DOMString'))
      item_info = self.TypeInfo(match.group(1) or match.group(2))
      return SequenceIDLTypeInfo(type_name, TypeData('Sequence'), item_info)
    if not type_name in _idl_type_registry:
      return InterfaceIDLTypeInfo(type_name, TypeData('Interface'))
    type_data = _idl_type_registry.get(type_name)
    class_name = '%sIDLTypeInfo' % type_data.clazz
    return globals()[class_name](type_name, type_data)
