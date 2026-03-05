package org.opencds.config.service;

import org.opencds.common.cache.CacheRegion;
import org.opencds.config.api.cache.CacheService;
import org.opencds.config.api.dao.CdsHooksClientDao;
import org.opencds.config.api.model.CdsHooksClient;
import org.opencds.config.api.service.CdsHooksClientService;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.stream.Collectors;

public class CdsHooksClientServiceImpl implements CdsHooksClientService {
    private static final CacheRegion<String, CdsHooksClient> CDS_HOOKS_CLIENT =
            CacheRegion.create(String.class, CdsHooksClient.class);

    private final CdsHooksClientDao dao;
    private final CacheService cacheService;

    public CdsHooksClientServiceImpl(CdsHooksClientDao dao,
                                     CacheService cacheService) {
        this.dao = dao;
        this.cacheService = cacheService;
        this.cacheService.putAll(CDS_HOOKS_CLIENT, buildPairs(dao.getAll()));
    }

    @Override
    public CdsHooksClient find(String clientId) {
        return cacheService.get(CDS_HOOKS_CLIENT, clientId);
    }

    @Override
    public List<CdsHooksClient> getAll() {
        return cacheService.getAll(CDS_HOOKS_CLIENT).values().stream()
                .toList();
    }

    @Override
    public List<CdsHooksClient> getAll(Predicate<CdsHooksClient> predicate) {
        return cacheService.getAll(CDS_HOOKS_CLIENT).values().stream()
                .filter(predicate)
                .toList();
    }

    @Override
    public void persist(CdsHooksClient hooksClient) {
        dao.persist(hooksClient);
        cacheService.put(CDS_HOOKS_CLIENT, hooksClient.id(), hooksClient);
    }

    @Override
    public void persist(List<CdsHooksClient> hooksClients) {
        dao.persist(hooksClients);
        cacheService.putAll(CDS_HOOKS_CLIENT, buildPairs(hooksClients));
    }

    @Override
    public void delete(String clientId) {
        Optional.ofNullable(find(clientId))
                .ifPresent(client -> {
                    dao.delete(client);
                    cacheService.evict(CDS_HOOKS_CLIENT, clientId);
                });
    }

    private Map<String, CdsHooksClient> buildPairs(List<CdsHooksClient> all) {
        return all.stream()
                .collect(Collectors.toMap(CdsHooksClient::id, Function.identity()));
    }

}
