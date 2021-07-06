
#ifndef SRC_REPLY_PARSER_H_
#define SRC_REPLY_PARSER_H_

#include <stddef.h>

/* ----------------------------------------------------------------------------------------
 * A resp parser used to parse replies returned by RM_Call
 * or Lua redis.call. The parser introduce callbacks
 * that needs to be set by the user. Each callback represents
 * a different reply type. Each callback gets a p_ctx that
 * was given to the parseReply function. The callbacks also give the
 * protocol (underline blob) of the current reply and the size.
 *
 * 3 special callbacks also get the parser object itself
 * (array_callback, set_callback, map_callback). This is because
 * it's their responsibility to continue the parsing by calling
 * parseReply. When the user continues parsing he can give a
 * different p_ctx (this is used by CallReply to give the nested reply as the p_ctx).
 * Also notice that those 3 callbacks do not get the proto len, this is because
 * When calling those callbacks the proto len is still unknown. the user
 * can calculate the len after finish parsing the entire collection.
 * ---------------------------------------------------------------------------------------- */

typedef struct ReplyParser {
    /* The current location on the reply buffer, need to set to the beginning of the reply*/
    const char* curr_location;

    /* Called when the parser reach an empty mbulk ('*-1') */
    void (*empty_mbulk_callback)(void* ctx, const char* proto, size_t proto_len);

    /* Called when the parser reach an empty bulk ('$-1') (bulk len is -1) */
    void (*empty_bulk_callback)(void* ctx, const char* proto, size_t proto_len);

    /* Called when the parser reach a bulk ('$'), given the bulk payload and size */
    void (*bulk_callback)(void* ctx, const char* str, size_t len, const char* proto, size_t proto_len);

    /* Called when the parser reach an error ('-'), given the error message and len */
    void (*error_callback)(void* ctx, const char* str, size_t len, const char* proto, size_t proto_len);

    /* Called when the parser reach a simple string ('+'), given the string message and len */
    void (*simple_str_callback)(void* ctx, const char* str, size_t len, const char* proto, size_t proto_len);

    /* Called when the parser reach a long long value (':'), the long long value is given as an argument*/
    void (*long_callback)(void* ctx, long long val, const char* proto, size_t proto_len);

    /* Called when the parser reach an array ('*'), the array size is given as an argument*/
    void (*array_callback)(struct ReplyParser* parser, void* ctx, size_t len, const char* proto);

    /* Called when the parser reach a set ('~'), the set size is given as an argument*/
    void (*set_callback)(struct ReplyParser* parser, void* ctx, size_t len, const char* proto);

    /* Called when the parser reach a map ('%'), the map size is given as an argument*/
    void (*map_callback)(struct ReplyParser* parser, void* ctx, size_t len, const char* proto);

    /* Called when the parser reach a bool ('#'), the boolean value is given as an argument*/
    void (*bool_callback)(void* ctx, int val, const char* proto, size_t proto_len);

    /* Called when the parser reach a double (','), the double value is given as an argument*/
    void (*double_callback)(void* ctx, double val, const char* proto, size_t proto_len);

    /* Called when the parser reach a null ('_') */
    void (*null_callback)(void* ctx, const char* proto, size_t proto_len);

    void (*error)(void* ctx);
} ReplyParser ;

int parseReply(ReplyParser* parser, void* p_ctx);

#endif /* SRC_REPLY_PARSER_H_ */
