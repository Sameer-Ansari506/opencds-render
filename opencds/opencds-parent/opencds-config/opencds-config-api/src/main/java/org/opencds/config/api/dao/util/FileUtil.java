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

package org.opencds.config.api.dao.util;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import java.io.File;
import java.io.FileFilter;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

public class FileUtil implements ResourceUtil {
    private static final Log log = LogFactory.getLog(FileUtil.class);
    /**
     * TODO FIXME: Does not handle symlinks...
     *
     * @param file
     * @return
     */
    @Override
    public List<String> findFiles(File file, boolean traverse) {
        if (!file.isDirectory()) {
            throw new IllegalArgumentException("File is not a directory: " + file.getAbsolutePath());
        }
        var children = Optional.ofNullable(file.listFiles())
                .orElseGet(() -> new File[]{});
        var files = new ArrayList<String>();
        for (File child : children) {
            if (child.isDirectory()) {
                if (traverse) {
                    files.addAll(findFiles(child, traverse)); // recursive--does not handle symlinks
                }
            } else {
                files.add(child.getAbsolutePath());
            }
        }
        return files;
    }

    @Override
    public InputStream getResourceAsStream(String resource) {
        try {
            return new FileInputStream(resource);
        } catch (FileNotFoundException e) {
            log.error(e.getMessage());
        }
        return null;
    }

    /**
     * Returns an ArrayList containing fileName String objects in the specified
     * file path, with the file name starting with and ending with the strings
     * specified. Sample filePath: "C:\Temp\Folder1" or "C:\Temp\Folder1\".
     * (both types ok --> tested).
     *
     * @param path
     * @param startsWith
     * @param endsWith
     * @return
     */
    @Override
    public List<String> listMatchingResources(final String path, final String startsWith, final String endsWith) {
        FileFilter filter = new FileFilter() {
            @Override
            public boolean accept(File pathname) {
                return ((startsWith == null || startsWith.isEmpty() || pathname.getName().startsWith(startsWith)) && (endsWith == null
                        || endsWith.isEmpty() || pathname.getName().endsWith(endsWith)));
            }
        };

        File parentDirectory = new File(path);
        File[] files = parentDirectory.listFiles(filter);

        List<String> fileNameList = new ArrayList<String>();
        if (files != null) {
            for (File file : files) {
                fileNameList.add(file.getName());
            }
        }
        return fileNameList;
    }

    public void delete(File rawStoreLoc) {
        for (File file : rawStoreLoc.listFiles()) {
            if (file.isDirectory()) {
                delete(file);
            }
            file.delete();
        }
        rawStoreLoc.delete();
    }

}
