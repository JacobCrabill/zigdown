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

[
 "delete"
 "new"
] @function.builtin

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
 "class"
 "enum"
 "struct"
 "union"
] @keyword.type

[
 "throw"
 "try"
 "catch"
] @keyword.exception

[
 "if"
 "else"
 "switch"
 "case"
] @keyword.conditional

[
 "continue"
 "do"
 "while"
 "for"
 "break"
] @keyword.repeat

[
 "const"
 "constexpr"
 "constinit"
 "consteval"
 "explicit"
 "extern"
 "inline"
 "mutable"
 "override"
 "private"
 "protected"
 "public"
 "static"
 "template"
 "volatile"
 "virtual"
] @keyword.modifier

"return" @keyword.return

[
  "and"
  "or"
] @keyword.operator

[
 "co_await"
 "co_return"
 "co_yield"
 "final"
 "friend"
 "namespace"
 "noexcept"
 "typename"
 "typedef"
 "using"
 "concept"
 "requires"
 "sizeof"
 "using"
] @keyword

(preproc_directive) @keyword.directive

; Strings

(string_literal) @string
(system_lib_string) @string
(raw_string_literal) @string

[
  "--"
  "-"
  "-="
  "->"
  "="
  "!="
  "*"
  "&"
  "&&"
  "&="
  "+"
  "++"
  "+="
  "<"
  "<<"
  "=="
  ">"
  ">>"
  "|"
  "||"
  "|="
] @operator

[
  "["
  "]"
  "{"
  "}"
  "("
  ")"
] @punctuation.bracket

[
  "."
  "::"
  ";"
] @punctuation.delimiter

(comment) @comment
