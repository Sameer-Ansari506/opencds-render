package org.opencds.common.utilities;

import java.lang.reflect.InvocationTargetException;

public class ClassUtil {
    public static <T> T newInstance(String className) {
        try {
        return newInstance((Class<T>) Class.forName(className));
        } catch (ClassNotFoundException e) {
            throw new RuntimeException(e);
        }
    }

    public static <T> T newInstance(Class<T> cls) {
        try {
            return (T) cls.getDeclaredConstructor().newInstance();
        } catch (InstantiationException | IllegalAccessException | InvocationTargetException | NoSuchMethodException e) {
            throw new RuntimeException(e);
        }
    }
}
