/// Resource pooling implementation for efficient resource management
import 'dart:async';
import 'dart:collection';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import '../types/hardware_types.dart';
import '../hal/hal_interface.dart';

/// Resource pool configuration
class ResourcePoolConfig {
  /// Maximum number of resources in the pool
  final int maxSize;
  
  /// Minimum number of resources to maintain
  final int minSize;
  
  /// Time to wait for a resource before timeout (milliseconds)
  final int acquireTimeout;
  
  /// Time before an idle resource is evicted (milliseconds)
  final int idleTimeout;
  
  /// Whether to validate resources before returning from pool
  final bool validateOnAcquire;
  
  /// Whether to validate resources before returning to pool
  final bool validateOnRelease;
  
  const ResourcePoolConfig({
    this.maxSize = 10,
    this.minSize = 0,
    this.acquireTimeout = 5000,
    this.idleTimeout = 300000, // 5 minutes
    this.validateOnAcquire = true,
    this.validateOnRelease = false,
  });
}

/// Resource wrapper for pooling
class PooledResource<T> {
  final T resource;
  final DateTime createdAt;
  DateTime lastUsedAt;
  int useCount;
  bool isValid;
  
  PooledResource({
    required this.resource,
    required this.createdAt,
  })  : lastUsedAt = createdAt,
        useCount = 0,
        isValid = true;
  
  /// Check if resource has been idle too long
  bool isIdleExpired(int idleTimeoutMs) {
    final idleDuration = DateTime.now().difference(lastUsedAt);
    return idleDuration.inMilliseconds > idleTimeoutMs;
  }
  
  /// Mark resource as used
  void markUsed() {
    lastUsedAt = DateTime.now();
    useCount++;
  }
}

/// Abstract resource pool
abstract class ResourcePool<T> {
  final ResourcePoolConfig config;
  final Logger _logger;
  final Queue<PooledResource<T>> _available = Queue();
  final Set<PooledResource<T>> _inUse = {};
  final List<Completer<PooledResource<T>>> _waiters = [];
  Timer? _evictionTimer;
  bool _isDisposed = false;
  
  ResourcePool({
    required this.config,
    required String name,
  }) : _logger = Logger('ResourcePool.$name') {
    // Start eviction timer
    _evictionTimer = Timer.periodic(
      Duration(seconds: 30),
      (_) => evictIdleResources(),
    );
    
    // Initialize minimum resources
    _initializeMinResources();
  }
  
  /// Create a new resource
  Future<T> createResource();
  
  /// Validate a resource
  Future<bool> validateResource(T resource);
  
  /// Destroy a resource
  Future<void> destroyResource(T resource);
  
  /// Get current pool size
  int get size => _available.length + _inUse.length;
  
  /// Get available resource count
  int get availableCount => _available.length;
  
  /// Get in-use resource count
  int get inUseCount => _inUse.length;
  
  /// Acquire a resource from the pool
  Future<T> acquire() async {
    if (_isDisposed) {
      throw StateError('Pool has been disposed');
    }
    
    final completer = Completer<PooledResource<T>>();
    
    // Try to get available resource
    final resource = await _tryAcquire();
    if (resource != null) {
      completer.complete(resource);
    } else {
      // Add to waiters
      _waiters.add(completer);
      
      // Set timeout
      Timer(Duration(milliseconds: config.acquireTimeout), () {
        if (!completer.isCompleted) {
          _waiters.remove(completer);
          completer.completeError(
            TimeoutException('Resource acquisition timeout', 
                Duration(milliseconds: config.acquireTimeout)),
          );
        }
      });
    }
    
    final pooledResource = await completer.future;
    return pooledResource.resource;
  }
  
  /// Release a resource back to the pool
  Future<void> release(T resource) async {
    if (_isDisposed) {
      await destroyResource(resource);
      return;
    }
    
    // Find the pooled resource
    final pooledResource = _inUse.firstWhere(
      (pr) => pr.resource == resource,
      orElse: () => throw ArgumentError('Resource not from this pool'),
    );
    
    _inUse.remove(pooledResource);
    
    // Validate if configured
    if (config.validateOnRelease) {
      final isValid = await validateResource(resource);
      if (!isValid) {
        _logger.warning('Resource failed validation on release');
        await destroyResource(resource);
        await _ensureMinimumResources();
        return;
      }
    }
    
    // Check if any waiters
    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeAt(0);
      pooledResource.markUsed();
      _inUse.add(pooledResource);
      waiter.complete(pooledResource);
    } else {
      // Return to available pool
      _available.add(pooledResource);
    }
  }
  
  /// Dispose of the pool
  Future<void> dispose() async {
    _isDisposed = true;
    _evictionTimer?.cancel();
    
    // Cancel all waiters
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('Pool is being disposed'));
      }
    }
    _waiters.clear();
    
    // Destroy all resources
    final allResources = [..._available, ..._inUse];
    for (final pooledResource in allResources) {
      try {
        await destroyResource(pooledResource.resource);
      } catch (e) {
        _logger.warning('Error destroying resource: $e');
      }
    }
    
    _available.clear();
    _inUse.clear();
  }
  
  /// Try to acquire an available resource
  Future<PooledResource<T>?> _tryAcquire() async {
    // Check available pool
    while (_available.isNotEmpty) {
      final pooledResource = _available.removeFirst();
      
      // Check if idle expired
      if (pooledResource.isIdleExpired(config.idleTimeout)) {
        await destroyResource(pooledResource.resource);
        continue;
      }
      
      // Validate if configured
      if (config.validateOnAcquire) {
        final isValid = await validateResource(pooledResource.resource);
        if (!isValid) {
          await destroyResource(pooledResource.resource);
          continue;
        }
      }
      
      // Mark as in use
      pooledResource.markUsed();
      _inUse.add(pooledResource);
      return pooledResource;
    }
    
    // Try to create new resource if under max size
    if (size < config.maxSize) {
      try {
        final resource = await createResource();
        final pooledResource = PooledResource(
          resource: resource,
          createdAt: DateTime.now(),
        );
        pooledResource.markUsed();
        _inUse.add(pooledResource);
        return pooledResource;
      } catch (e) {
        _logger.warning('Failed to create resource: $e');
      }
    }
    
    return null;
  }
  
  /// Initialize minimum resources
  void _initializeMinResources() {
    // Don't block constructor - initialize async
    Future.microtask(() => _ensureMinimumResources());
  }
  
  /// Ensure minimum resources are available
  Future<void> _ensureMinimumResources() async {
    while (size < config.minSize && !_isDisposed) {
      try {
        final resource = await createResource();
        final pooledResource = PooledResource(
          resource: resource,
          createdAt: DateTime.now(),
        );
        _available.add(pooledResource);
      } catch (e) {
        _logger.warning('Failed to create minimum resource: $e');
        break;
      }
    }
  }
  
  /// Evict idle resources
  @visibleForTesting
  Future<void> evictIdleResources() async {
    if (_isDisposed) return;
    
    final toEvict = <PooledResource<T>>[];
    
    // Check available resources for idle timeout
    for (final pooledResource in _available) {
      if (pooledResource.isIdleExpired(config.idleTimeout) && 
          size > config.minSize) {
        toEvict.add(pooledResource);
      }
    }
    
    // Evict idle resources
    for (final pooledResource in toEvict) {
      _available.remove(pooledResource);
      try {
        await destroyResource(pooledResource.resource);
      } catch (e) {
        _logger.warning('Error evicting resource: $e');
      }
    }
    
    // Ensure minimum resources
    await _ensureMinimumResources();
  }
  
  /// Get pool statistics
  Map<String, dynamic> getStatistics() {
    return {
      'size': size,
      'available': availableCount,
      'inUse': inUseCount,
      'waiters': _waiters.length,
      'minSize': config.minSize,
      'maxSize': config.maxSize,
    };
  }
}

/// GPIO resource pool
class GpioResourcePool extends ResourcePool<GpioPin> {
  final GpioProvider provider;
  final int pin;
  final GpioConfig gpioConfig;
  
  GpioResourcePool({
    required this.provider,
    required this.pin,
    required this.gpioConfig,
    ResourcePoolConfig? poolConfig,
  }) : super(
          config: poolConfig ?? const ResourcePoolConfig(maxSize: 1),
          name: 'GPIO_$pin',
        );
  
  @override
  Future<GpioPin> createResource() async {
    await provider.configurePin(gpioConfig);
    return GpioPin(provider, pin);
  }
  
  @override
  Future<bool> validateResource(GpioPin resource) async {
    // Check if pin is still accessible
    try {
      await provider.readPin(pin);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Future<void> destroyResource(GpioPin resource) async {
    // GPIO pins don't need explicit cleanup
  }
}

/// GPIO pin wrapper
class GpioPin {
  final GpioProvider provider;
  final int pin;
  
  GpioPin(this.provider, this.pin);
  
  Future<bool> read() => provider.readPin(pin);
  Future<void> write(bool value) => provider.writePin(pin, value);
}

/// I2C bus resource pool
class I2cBusResourcePool extends ResourcePool<I2cBus> {
  final I2cProvider provider;
  final int bus;
  
  I2cBusResourcePool({
    required this.provider,
    required this.bus,
    ResourcePoolConfig? poolConfig,
  }) : super(
          config: poolConfig ?? const ResourcePoolConfig(maxSize: 5),
          name: 'I2C_Bus_$bus',
        );
  
  @override
  Future<I2cBus> createResource() async {
    return await provider.openBus(bus);
  }
  
  @override
  Future<bool> validateResource(I2cBus resource) async {
    // Perform a simple read to validate bus
    try {
      // Try to read from address 0x00 (general call address)
      await resource.read(0x00, 1);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Future<void> destroyResource(I2cBus resource) async {
    await resource.close();
  }
}

/// SPI device resource pool
class SpiDeviceResourcePool extends ResourcePool<SpiDevice> {
  final SpiProvider provider;
  final SpiConfig spiConfig;
  
  SpiDeviceResourcePool({
    required this.provider,
    required this.spiConfig,
    ResourcePoolConfig? poolConfig,
  }) : super(
          config: poolConfig ?? const ResourcePoolConfig(maxSize: 3),
          name: 'SPI_Device_${spiConfig.device}',
        );
  
  @override
  Future<SpiDevice> createResource() async {
    return await provider.openDevice(spiConfig);
  }
  
  @override
  Future<bool> validateResource(SpiDevice resource) async {
    // SPI devices are generally always valid once opened
    return true;
  }
  
  @override
  Future<void> destroyResource(SpiDevice resource) async {
    await resource.close();
  }
}

/// UART port resource pool
class UartPortResourcePool extends ResourcePool<UartPort> {
  final UartProvider provider;
  final UartConfig uartConfig;
  
  UartPortResourcePool({
    required this.provider,
    required this.uartConfig,
    ResourcePoolConfig? poolConfig,
  }) : super(
          config: poolConfig ?? const ResourcePoolConfig(maxSize: 1),
          name: 'UART_${uartConfig.port}',
        );
  
  @override
  Future<UartPort> createResource() async {
    return await provider.openPort(uartConfig);
  }
  
  @override
  Future<bool> validateResource(UartPort resource) async {
    // Check if port is still open
    try {
      // Most UART implementations will throw if port is closed
      await resource.writeString('');
      return true;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Future<void> destroyResource(UartPort resource) async {
    await resource.close();
  }
}

/// Resource pool manager
class ResourcePoolManager {
  final Map<String, ResourcePool> _pools = {};
  final Logger _logger = Logger('ResourcePoolManager');
  
  /// Get or create a GPIO resource pool
  GpioResourcePool getGpioPool({
    required GpioProvider provider,
    required int pin,
    required GpioConfig gpioConfig,
    ResourcePoolConfig? poolConfig,
  }) {
    final key = 'gpio_$pin';
    return _pools.putIfAbsent(key, () => GpioResourcePool(
      provider: provider,
      pin: pin,
      gpioConfig: gpioConfig,
      poolConfig: poolConfig,
    )) as GpioResourcePool;
  }
  
  /// Get or create an I2C bus resource pool
  I2cBusResourcePool getI2cPool({
    required I2cProvider provider,
    required int bus,
    ResourcePoolConfig? poolConfig,
  }) {
    final key = 'i2c_bus_$bus';
    return _pools.putIfAbsent(key, () => I2cBusResourcePool(
      provider: provider,
      bus: bus,
      poolConfig: poolConfig,
    )) as I2cBusResourcePool;
  }
  
  /// Get or create a SPI device resource pool
  SpiDeviceResourcePool getSpiPool({
    required SpiProvider provider,
    required SpiConfig spiConfig,
    ResourcePoolConfig? poolConfig,
  }) {
    final key = 'spi_device_${spiConfig.device}';
    return _pools.putIfAbsent(key, () => SpiDeviceResourcePool(
      provider: provider,
      spiConfig: spiConfig,
      poolConfig: poolConfig,
    )) as SpiDeviceResourcePool;
  }
  
  /// Get or create a UART port resource pool
  UartPortResourcePool getUartPool({
    required UartProvider provider,
    required UartConfig uartConfig,
    ResourcePoolConfig? poolConfig,
  }) {
    final key = 'uart_${uartConfig.port}';
    return _pools.putIfAbsent(key, () => UartPortResourcePool(
      provider: provider,
      uartConfig: uartConfig,
      poolConfig: poolConfig,
    )) as UartPortResourcePool;
  }
  
  /// Get pool statistics
  Map<String, Map<String, dynamic>> getAllStatistics() {
    final stats = <String, Map<String, dynamic>>{};
    _pools.forEach((key, pool) {
      stats[key] = pool.getStatistics();
    });
    return stats;
  }
  
  /// Dispose all pools
  Future<void> dispose() async {
    for (final pool in _pools.values) {
      try {
        await pool.dispose();
      } catch (e) {
        _logger.warning('Error disposing pool: $e');
      }
    }
    _pools.clear();
  }
}