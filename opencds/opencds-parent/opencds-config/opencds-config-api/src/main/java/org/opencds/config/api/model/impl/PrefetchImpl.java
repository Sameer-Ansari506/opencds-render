/*
 * Copyright 2020 OpenCDS.org
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

package org.opencds.config.api.model.impl;

import org.opencds.config.api.model.Prefetch;
import org.opencds.config.api.model.Resource;

import java.util.Collections;
import java.util.List;

public record PrefetchImpl(List<Resource> resources) implements Prefetch {
    public PrefetchImpl {
        resources = resources == null ? Collections.emptyList() : Collections.unmodifiableList(resources);
    }

    public static Prefetch create(List<Resource> resources) {
        return new PrefetchImpl(resources);
    }

    public static Prefetch create(Prefetch prefetch) {
        if (prefetch == null) {
            return null;
        }
        if (prefetch instanceof PrefetchImpl prefetchImpl) {
            return prefetchImpl;
        }
        return create(prefetch.getResources());
    }

    public static Prefetch empty() {
        return new PrefetchImpl(Collections.emptyList());
    }

    @Override
    public List<Resource> getResources() {
        return resources;
    }

}
