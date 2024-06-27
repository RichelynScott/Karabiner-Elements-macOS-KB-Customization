#pragma once

#include "async_file_writer.hpp"
#include "json_utility.hpp"
#include "logger.hpp"
#include <fstream>
#include <optional>
#include <pqrs/filesystem.hpp>
#include <unistd.h>

namespace krbn {
class json_writer final {
public:
  template <typename T>
  static void async_save_to_file(const T& json,
                                 const std::string& file_path,
                                 mode_t parent_directory_mode,
                                 mode_t file_mode) {
    async_file_writer::enqueue(file_path,
                               json_utility::dump(json),
                               parent_directory_mode,
                               file_mode);
  }

  template <typename T>
  static void sync_save_to_file(const T& json,
                                const std::string& file_path,
                                mode_t parent_directory_mode,
                                mode_t file_mode) {
    async_save_to_file(json,
                       file_path,
                       parent_directory_mode,
                       file_mode);

    async_file_writer::wait();
  }
};
} // namespace krbn
