/*
 * Copyright 2014-2020 OpenCDS.org
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.opencds.config.api.dao.file;

import org.apache.commons.lang3.StringUtils;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Objects;

public record FileCacheElement(String id,
                               Path location) implements CacheElement {

    public FileCacheElement {
        assert StringUtils.isNotBlank(id);
        assert location != null;
    }

    public static FileCacheElement create(String id, Path cacheFileLocation) {
        return new FileCacheElement(id, cacheFileLocation);
    }

    @Override
    public String getId() {
        return id;
    }

    @Override
    public boolean exists() {
        return getFile().exists();
    }

    @Override
    public long length() {
        return getFile().length();
    }

    @Override
    public File getFile() {
        return Paths.get(location.toString(), id).toFile();
    }

    @Override
    public InputStream getInputStream() throws IOException {
        return new FileInputStream(getFile());
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        FileCacheElement that = (FileCacheElement) o;
        return Objects.equals(id, that.id) && Objects.equals(location, that.location);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id, location);
    }

    @Override
    public String toString() {
        return "FileCacheElement{" +
                "id='" + id + '\'' +
                ", location=" + location +
                '}';
    }
}
