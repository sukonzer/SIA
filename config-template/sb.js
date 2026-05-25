const { type, name } = $arguments
const compatible_outbound = {
  tag: 'COMPATIBLE',
  type: 'direct',
}

let compatible
const config = JSON.parse($files[0])
const proxies = await produceArtifact({
  name,
  type: /^1$|col/i.test(type) ? 'collection' : 'subscription',
  platform: 'sing-box',
  produceType: 'internal',
})

// 返回过滤后的节点tag组
function filterProxies(proxies, filter) {
  if (Array.isArray(filter)) {
    return proxies.filter(proxy => {
      return filter.some(f => {
        if (f.action === 'include' && Array.isArray(f.keywords)) {
          return f.keywords.some(keyword => {
            return proxy.tag && proxy.tag.match(new RegExp(keyword, 'i'))
          })
        } else if (f.action === 'exclude' && Array.isArray(f.keywords)) {
          return !f.keywords.some(keyword => {
            return proxy.tag && proxy.tag.match(new RegExp(keyword, 'i'))
          })
        }
      })
    }).map(proxy => proxy.tag)
  } else {
    return proxies.map(proxy => proxy.tag)
  }
}

// 先填入全部节点
config.outbounds.push(...proxies)

// 找出配置中存在{all}占位的项，根据其filter条件进行过滤
config.outbounds.forEach(obd => {
  if (obd.outbounds?.includes("{all}")) {
    obd.outbounds = filterProxies(proxies, obd.filter)
    delete obd.filter
  }
})

// 最后对空节点添加容错
config.outbounds.forEach(outbound => {
  if (Array.isArray(outbound.outbounds) && outbound.outbounds.length === 0) {
    if (!compatible) {
      config.outbounds.push(compatible_outbound)
      compatible = true
    }
    outbound.outbounds.push(compatible_outbound.tag)
  }
})

// 动态追加唯一cache_id
if (config?.experimental?.cache_file) {
  Object.assign(config.experimental.cache_file, { cache_id: name })
}

$content = JSON.stringify(config, null, 2)