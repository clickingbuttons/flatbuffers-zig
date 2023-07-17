#include "File_generated.h"

extern "C" bool verifyFooter(char* buf, size_t len) {
	const Footer* footer = GetFooter(buf);

  flatbuffers::Verifier verifier(
      (const uint8_t*) buf, len,
      /*max_depth=*/128,
      /*max_tables=*/static_cast<flatbuffers::uoffset_t>(8 * len));
	return footer->Verify(verifier);
}
