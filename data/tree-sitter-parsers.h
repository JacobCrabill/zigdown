// #ifndef TREE_SITTER_PARSERS_H_
// #define TREE_SITTER_PARSERS_H_

typedef struct TSLanguage TSLanguage;

// #ifdef __cplusplus
// extern "C" {
// #endif

// TODO: Auto-generate from build.zig?
const TSLanguage *tree_sitter_bash(void);
const TSLanguage *tree_sitter_c(void);
const TSLanguage *tree_sitter_cpp(void);
const TSLanguage *tree_sitter_json(void);
const TSLanguage *tree_sitter_make(void);
const TSLanguage *tree_sitter_python(void);
const TSLanguage *tree_sitter_rust(void);
const TSLanguage *tree_sitter_yaml(void);
const TSLanguage *tree_sitter_zig(void);

// #ifdef __cplusplus
// }
// #endif
//
// #endif // TREE_SITTER_PARSERS_H_
