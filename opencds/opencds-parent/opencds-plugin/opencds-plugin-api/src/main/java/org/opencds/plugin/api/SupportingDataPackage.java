/*
 * Copyright 2017-2020 OpenCDS.org
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

package org.opencds.plugin.api;

import java.io.File;
import java.util.function.Supplier;

public record SupportingDataPackage(Supplier<File> fileSupplier, Supplier<byte[]> bytesSupplier) {
    public SupportingDataPackage {
        assert fileSupplier != null;
        assert bytesSupplier != null;
    }

    public static SupportingDataPackage create(Supplier<File> fileSupplier, Supplier<byte[]> bytesSupplier) {
        return new SupportingDataPackage(fileSupplier, bytesSupplier);
    }

    public File getFile() {
        return fileSupplier.get();
    }

    public byte[] getBytes() {
        return bytesSupplier.get();
    }
}
