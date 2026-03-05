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

package org.opencds.config.service;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.opencds.common.cache.CacheRegion;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.dao.FileDao;
import org.opencds.config.api.dao.file.CacheElement;
import org.opencds.config.api.dao.file.FileCacheElement;
import org.opencds.config.api.dao.file.StreamCacheElement;
import org.opencds.config.api.model.SupportingData;
import org.opencds.config.api.service.SupportingDataPackageService;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.Optional;
import java.util.stream.Collectors;

public class SupportingDataPackageServiceImpl implements SupportingDataPackageService {
    private static final Log log = LogFactory.getLog(SupportingDataPackageServiceImpl.class);
    private static final CacheRegion<CacheElement, byte[]> SD_PACKAGE_BYTES =
            CacheRegion.create(CacheElement.class, byte[].class);

    private final FileDao fileDao;

    private final CacheService cacheService;

    public SupportingDataPackageServiceImpl(FileDao fileDao, CacheService cacheService) {
        this.fileDao = fileDao;
        this.cacheService = cacheService;
    }

    @Override
    public boolean exists(SupportingData supportingData) {
        return Optional.ofNullable(supportingData)
                .map(this::packageIdOrSDId)
                .map(fileDao::find)
                .map(CacheElement::exists)
                .orElse(false);
    }

    @Override
    public InputStream getPackageInputStream(SupportingData supportingData) {
        return Optional.ofNullable(supportingData)
                .map(this::packageIdOrSDId)
                .map(fileDao::find)
                .filter(CacheElement::exists)
                .map(cacheElement -> {
                    try {
                        return cacheElement.getInputStream();
                    } catch (IOException e) {
                        log.error("Cannot resolve package: " + supportingData.getPackageId());
                        return null;
                    }
                })
                .orElse(null);
    }

    @Override
    public byte[] getPackageBytes(SupportingData supportingData) {
        CacheElement cacheElement = fileDao.find(packageIdOrSDId(supportingData));
        byte[] bytes = cacheService.get(SD_PACKAGE_BYTES, cacheElement);
        if (bytes == null || bytes.length == 0) {
            try (BufferedReader is = new BufferedReader(new InputStreamReader(cacheElement.getInputStream()))) {
                return is.lines().collect(Collectors.joining()).getBytes();
            } catch (IOException e) {
                log.error("Error reading CacheElement: " + cacheElement, e);
            }
        }
        return bytes;
    }

	@Override
	public File getFile(SupportingData supportingData) {
        return Optional.ofNullable(supportingData)
                .map(this::packageIdOrSDId)
                .map(fileDao::find)
                .filter(CacheElement::exists)
                .filter(FileCacheElement.class::isInstance)
                .map(FileCacheElement.class::cast)
                .map(FileCacheElement::getFile)
                .orElse(null);
	}

    @Override
    public void persistPackageInputStream(SupportingData sd, InputStream supportingDataPackage) {
        var cacheElement = StreamCacheElement.create(packageIdOrSDId(sd), supportingDataPackage);
        fileDao.persist(cacheElement);
    }

    @Override
    public void deletePackage(SupportingData sd) {
        String packageId = sd.getPackageId();
        if (packageId != null) {
            CacheElement cacheElement = fileDao.find(packageId);
            if (cacheElement != null) {
                fileDao.delete(cacheElement);
                cacheService.evict(SD_PACKAGE_BYTES, cacheElement);
            }
        }
    }

    private String packageIdOrSDId(SupportingData sd) {
        return Optional.ofNullable(sd.getPackageId())
                .orElseGet(sd::getIdentifier);
    }
}
