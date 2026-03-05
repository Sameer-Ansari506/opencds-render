package org.opencds.config.file.dao;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.opencds.config.api.dao.CdsHooksClientDao;
import org.opencds.config.api.dao.util.ResourceUtil;
import org.opencds.config.api.model.CdsHooksClient;
import org.opencds.config.mapper.util.RestConfigUtil;

import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class CdsHooksClientFileDao implements CdsHooksClientDao {
    private static final Log log = LogFactory.getLog(CdsHooksClientFileDao.class);
    private final Map<String, CdsHooksClient> cache;

    public CdsHooksClientFileDao(ResourceUtil resourceUtil, Path path) {
        cache = new HashMap<>();
        var restConfigUtil = new RestConfigUtil();
        log.info("Loading resource: " + path);
        restConfigUtil.unmarshalCdsHooksClients(
                resourceUtil.getResourceAsStream(path.toString()))
                .forEach(client -> cache.put(client.id(), client));
    }

    @Override
    public CdsHooksClient find(String clientId) {
        return cache.get(clientId);
    }

    @Override
    public List<CdsHooksClient> getAll() {
        return cache.values().stream().toList();
    }

    @Override
    public void persist(CdsHooksClient hooksClient) {
        throw new UnsupportedOperationException("Cannot persist to file store through dao API");
    }

    @Override
    public void persist(List<CdsHooksClient> hooksClients) {
        throw new UnsupportedOperationException("Cannot persist to file store through dao API");
    }

    @Override
    public void delete(CdsHooksClient hooksClient) {
        throw new UnsupportedOperationException("Cannot delete from file store through the dao API");
    }
}
