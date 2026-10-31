#include "NativeSupport.h"
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

static int transform(const uint8_t *input, size_t length, uint8_t **output,
                     size_t *output_length, int compress) {
  const size_t limit = 8 * 1024 * 1024;
  *output = NULL; *output_length = 0;
  if (length > limit) return Z_MEM_ERROR;
  z_stream stream = {0};
  int status = compress ? deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                                      15 + 16, 8, Z_DEFAULT_STRATEGY)
                        : inflateInit2(&stream, 15 + 32);
  if (status != Z_OK) return status;
  size_t capacity = length + 1024;
  if (capacity < 4096) capacity = 4096;
  uint8_t *buffer = malloc(capacity);
  if (!buffer) { status = Z_MEM_ERROR; goto done; }
  stream.next_in = (Bytef *)input;
  stream.avail_in = (uInt)length;
  do {
    if (stream.total_out == capacity) {
      size_t next = capacity * 2;
      if (next > limit) { status = Z_MEM_ERROR; break; }
      void *grown = realloc(buffer, next);
      if (!grown) { status = Z_MEM_ERROR; break; }
      buffer = grown; capacity = next;
    }
    stream.next_out = buffer + stream.total_out;
    stream.avail_out = (uInt)(capacity - stream.total_out);
    status = compress ? deflate(&stream, Z_FINISH) : inflate(&stream, Z_NO_FLUSH);
    if (!compress && status == Z_OK && stream.avail_in == 0) {
      status = Z_DATA_ERROR; break;
    }
  } while (status == Z_OK);
  if (status == Z_STREAM_END) {
    *output = buffer; *output_length = stream.total_out;
    buffer = NULL; status = Z_OK;
  }
  free(buffer);
done:
  if (compress) deflateEnd(&stream); else inflateEnd(&stream);
  return status;
}
int vt_gzip(const uint8_t *p, size_t n, uint8_t **o, size_t *l) { return transform(p,n,o,l,1); }
int vt_gunzip(const uint8_t *p, size_t n, uint8_t **o, size_t *l) { return transform(p,n,o,l,0); }
void vt_free(void *pointer) { free(pointer); }
