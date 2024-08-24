; Functions

(call_expression
  function: (qualified_identifier
    name: (identifier) @function))

(template_function
  name: (identifier) @function)

(template_method
  name: (field_identifier) @function)

(template_function
  name: (identifier) @function)

(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @function))

(function_declarator
  declarator: (field_identifier) @function)

(function_declarator
  declarator: (identifier) @function)

; Types

((namespace_identifier) @type
 (#match? @type "^[A-Z]"))

(auto) @type

(primitive_type) @type
(type_identifier) @type

(number_literal) @number

; Constants

(this) @variable.builtin
(null "nullptr" @constant)

; Keywords

[
 "break"
 "catch"
 "class"
 "co_await"
 "co_return"
 "co_yield"
 "const"
 "constexpr"
 "constinit"
 "consteval"
 "delete"
 "enum"
 "explicit"
 "extern"
 "final"
 "friend"
 "inline"
 "mutable"
 "namespace"
 "noexcept"
 "new"
 "override"
 "private"
 "protected"
 "public"
 "template"
 "throw"
 "try"
 "typename"
 "typedef"
 "using"
 "concept"
 "requires"
 "return"
 "sizeof"
 "static"
 "struct"
 "union"
 "using"
 "volatile"
 "if"
 "else"
 "while"
 "for"
 "switch"
 "case"
 (virtual)
] @keyword

"#include" @keyword
; Strings

(string_literal) @string
(system_lib_string) @string
(raw_string_literal) @string

"--" @operator
"-" @operator
"-=" @operator
"->" @operator
"=" @operator
"!=" @operator
"*" @operator
"&" @operator
"&&" @operator
"&=" @operator
"+" @operator
"++" @operator
"+=" @operator
"<" @operator
"<<" @operator
"==" @operator
">" @operator
">>" @operator
"|" @operator
"||" @operator
"|=" @operator
"[" @operator
"]" @operator

"{" @delimiter
"}" @delimiter
"(" @delimiter
")" @delimiter
"." @delimiter
"::" @delimiter
";" @delimiter

(comment) @comment
