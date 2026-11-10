// ClapEntry.cpp
// The exported clap_entry. clap-wrapper compiles this into the CLAP and wraps
// the same functions for the VST3 and AU builds.

#include <clap/clap.h>

#include "VSMusicianClap.h"

extern "C"
{
#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wattributes"
#endif

const CLAP_EXPORT struct clap_plugin_entry clap_entry = {
    CLAP_VERSION, vsm_entry_init, vsm_entry_deinit, vsm_entry_get_factory
};

#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif
}
