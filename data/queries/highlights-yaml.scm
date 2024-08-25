;; keys
(block_mapping_pair
 key: (flow_node [(double_quote_scalar) (single_quote_scalar)] @variable))
(block_mapping_pair
  key: (flow_node (plain_scalar (string_scalar) @keyword)))

;; keys within inline {} blocks
(flow_mapping
 (_ key: (flow_node [(double_quote_scalar) (single_quote_scalar)] @variable)))
(flow_mapping
 (_ key: (flow_node (plain_scalar (string_scalar) @variable))))

;; values
(block_mapping_pair
  value: (flow_node (plain_scalar (string_scalar) @string)))
(block_mapping_pair
  value: (block_node (block_scalar) @string))

;; strings, numbers, bools
[(double_quote_scalar) (single_quote_scalar) (block_scalar)] @string
[(null_scalar) (boolean_scalar)] @constant.builtin
[(integer_scalar) (float_scalar)] @number

["[" "]" "{" "}"] @punctuation.bracket
["," "-" ":" "?" ">" "|"] @punctuation.delimiter
["*" "&" "---" "..."] @punctuation.special

(escape_sequence) @escape

(comment) @comment
[(anchor_name) (alias_name)] @function
(yaml_directive) @type

(tag) @type
(tag_handle) @type
(tag_prefix) @string
(tag_directive) @property
