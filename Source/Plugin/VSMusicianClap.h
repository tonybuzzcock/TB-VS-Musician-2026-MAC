// VSMusicianClap.h
// The three entry functions clap-wrapper links into every format.

#pragma once

bool vsm_entry_init (const char* pluginPath);
void vsm_entry_deinit();
const void* vsm_entry_get_factory (const char* factoryId);
