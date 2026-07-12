;; extends

; ==============================================================================
; Template parameter declarations
; ==============================================================================

; template<typename T>
; template<class T>
(type_parameter_declaration
  (type_identifier) @type.parameter
  (#set! @type.parameter priority 120))

; template<typename... Ts>
(variadic_type_parameter_declaration
  (type_identifier) @type.parameter
  (#set! @type.parameter priority 120))

; template<typename T = void>
(optional_type_parameter_declaration
  name: (type_identifier) @type.parameter
  (#set! @type.parameter priority 120))

; Template-parameter references that clangd occasionally leaves without
; semantic tokens. Keep this list limited to established project conventions.
(
  [
    (identifier)
    (type_identifier)
  ] @type.parameter
  (#any-of? @type.parameter
    "T"
    "U"
    "V"
    "R"
    "To"
    "From"
    "Ts"
    "Us"
    "Args"
    "Fn"
    "Tuple"
    "Policy"
    "OtherT"
    "OtherPolicy")
  (#set! priority 115)
)

; ==============================================================================
; Named type declarations
; ==============================================================================

; using value_type = T;
(alias_declaration
  name: (type_identifier) @type.alias
  (#set! @type.alias priority 120))

; struct Foo {};
(struct_specifier
  name: (type_identifier) @type.struct.declaration
  (#set! @type.struct.declaration priority 120))

; class Foo {};
(class_specifier
  name: (type_identifier) @type.class.declaration
  (#set! @type.class.declaration priority 120))

; union Foo {};
(union_specifier
  name: (type_identifier) @type.union.declaration
  (#set! @type.union.declaration priority 120))

; enum Foo {};
(enum_specifier
  name: (type_identifier) @type.enum.declaration
  (#set! @type.enum.declaration priority 120))

; concept foo = ...;
(concept_definition
  name: (identifier) @type.concept.declaration
  (#set! @type.concept.declaration priority 130))


; ==============================================================================
; Common C++ naming conventions
; ==============================================================================

; Standard type aliases:
; remove_cvref_t, remove_pointer_t, value_type, etc.
([
  (identifier)
  (type_identifier)
] @type
  (#match? @type "(_t|_type)$")
  (#set! @type priority 110))

; Standard variable templates:
; is_reference_v, is_same_v, is_trivially_copyable_v, etc.
(identifier) @constant
  (#match? @constant "_v$")
  (#set! @constant priority 110)


; ==============================================================================
; Punctuation
; ==============================================================================

[
  "("
  ")"
] @punctuation.bracket.round
  (#set! @punctuation.bracket.round priority 105)

[
  "{"
  "}"
] @punctuation.bracket.curly
  (#set! @punctuation.bracket.curly priority 105)

[
  "["
  "]"
] @punctuation.bracket.square
  (#set! @punctuation.bracket.square priority 105)
