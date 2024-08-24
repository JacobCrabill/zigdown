(block_mapping_pair
  key: (flow_node (plain_scalar (string_scalar) @keyword)))

(block_mapping_pair
  value: (flow_node (plain_scalar (string_scalar) @string)))

(block_mapping_pair
  value: (block_node (block_scalar) @string))

(double_quote_scalar) @string

(integer_scalar) @number
(float_scalar) @number

(comment) @comment

[
 ":"
 ","
] @delimiter
