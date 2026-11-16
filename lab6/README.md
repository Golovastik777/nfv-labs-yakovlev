# ЛР6. Цепочка сервисных функций (SFC) и жизненный цикл VNF под управлением SDN

## Персональные параметры

| Параметр | Значение |
| --- | --- |
| Номер ИСУ | 315907 |
| `STUDENT` | `yakovlev` |
| `N` | `7` |
| Management-подсеть / ODL | `10.106.7.0/24` / `10.106.7.100` (sw — `10.106.7.10`) |
| client1 / client2 / server | `10.7.6.11` / `10.7.6.12` / `10.7.6.100` (/24) |
| Запрещённый порт (FW) | `8007` (8000 + 7) |
| Скорость шейпера | `17` Мбит/с (10 + 7 mod 10) |
| Имена цепочек | `yakovlev-c1`, `yakovlev-c2` |
| Где работаю | локально: Colima на Mac (ВМ Ubuntu 24.04 aarch64, 4 vCPU, 8 ГБ) |

## Стенд

- Docker в ВМ Colima. containerlab 0.82 запускается из официального образа `ghcr.io/srl-labs/clab`: обёртка в [scripts/env.sh](scripts/env.sh) включается, только если бинарника нет, и экспортируется (`export -f`), чтобы её видел `vnfm.sh` (`containerlab tools veth create`).
- Образы `odl:chromium`, `ovs-lab:latest`, `lab-tools:1.0` те же, что в ЛР4. `python3-requests`, `python3-yaml` и `envsubst` в ВМ уже были.
- Все команды выполняются внутри ВМ (`colima ssh`), из каталога `lab6` после `source scripts/env.sh`.
- Полные выводы всех шагов лежат в [logs/](logs/).

## Схема NFVI

```
                     ┌─────────────────────────────────────┐
                     │ odl 10.106.7.100  (SDN-контроллер)  │◄── nfvo.py: RESTCONF :8181
                     └──────────────────┬──────────────────┘
       management 10.106.7.0/24 (eth0)  │ OpenFlow 1.3 :6653
                     ┌──────────────────┴─────────────────────────────────────┐
                     │ sw (OVS br0, netdev, fail-mode secure, openflow:1)     │
                     │  1    2    3    4    5    6    7    8    9            │
                     └──┬────┬────┬────┬────┬────┬────┬────┬────┬────────────┘
   client1 10.7.6.11 ───┘    │    │    │    │    │    │    │    └─── server 10.7.6.100
   client2 10.7.6.12 ────────┘    │    │    │    │    │    │         (HTTP :80, :8007, iperf3)
                                 ┌┴────┴┐  ┌┴────┴┐ ┌─┴────┴─┐
                                 │ fw1  │  │ fw2  │ │ shaper1│
                                 │ br0  │  │ br0  │ │ br0    │
                                 └──────┘  └──────┘ └────────┘
                              nftables    scale-out tc tbf 17 Мбит/с, eth2
                              fw1 удалён  (этап 4)
```

Номер порта OpenFlow равен номеру `ethX` коммутатора (`ofport_request`). VNF работают «в разрыв» (bump-in-the-wire): внутри каждой мост `br0` из `eth1` (сторона клиентов) и `eth2` (сторона сервера), IP-адресов в сети данных у VNF нет. Клиенты и сервер в одной подсети `/24`, адресация не меняется: путь задают только потоки OpenFlow.

### Соответствие ETSI NFV MANO

| ETSI NFV | В этой работе |
| --- | --- |
| NFVI | ВМ Colima, Docker, OVS (userspace datapath `netdev`) |
| VIM | Docker + containerlab: создание контейнеров и veth-каналов |
| SDN-контроллер / WIM | OpenDaylight Chromium (OpenFlow Plugin, RESTCONF) |
| VNFM | [vnfm.sh](vnfm.sh): `configure`, `instantiate`, `terminate`, `list` |
| NFVO | [nfvo.py](nfvo.py): `apply`, `show`, `delete` по описанию VNFFG |
| VNFD | [descriptors/fw-vnfd.yaml](descriptors/fw-vnfd.yaml), [descriptors/shaper-vnfd.yaml](descriptors/shaper-vnfd.yaml) |
| VNFFGD | [vnffg.yaml](vnffg.yaml) |
| VNF | `fw1`, `fw2` (nftables), `shaper1` (tc tbf) |

## Таблица потоков цепочки c1

Каждый переход — два потока с приоритетом 300: IPv4 (`ethernet-type 0x0800`) и ARP (`0x0806`). В прямом направлении матч по адресу клиента как источника (`nw_src` / `arp_spa = 10.7.6.11`), в обратном — как получателя (`nw_dst` / `arp_tpa = 10.7.6.11`).

До heal (`path: [fw1, shaper1]`):

| Поток | Направление | in_port → out_port | Переход |
| --- | --- | --- | --- |
| `sfc-yakovlev-c1-fwd0` | прямое | 1 → 3 | client1 → fw1.eth1 |
| `sfc-yakovlev-c1-fwd1` | прямое | 4 → 7 | fw1.eth2 → shaper1.eth1 |
| `sfc-yakovlev-c1-fwd2` | прямое | 8 → 9 | shaper1.eth2 → server |
| `sfc-yakovlev-c1-rev0` | обратное | 9 → 8 | server → shaper1.eth2 |
| `sfc-yakovlev-c1-rev1` | обратное | 7 → 4 | shaper1.eth1 → fw1.eth2 |
| `sfc-yakovlev-c1-rev2` | обратное | 3 → 1 | fw1.eth1 → client1 |

После heal (`path: [fw2, shaper1]`) меняются только переходы через FW: `fwd0` 1 → 5, `fwd1` 6 → 7, `rev1` 7 → 6, `rev2` 5 → 1. Цепочка c2 устроена так же с адресом `10.7.6.12` и входом через порт 2. Всего 2 цепочки × 6 переходов × 2 протокола = 24 потока. Вывод `dump-flows`: [logs/3.1-apply.txt](logs/3.1-apply.txt).

## Запуск

```bash
cd ~/nfv-labs-yakovlev/lab6 && source scripts/env.sh
containerlab deploy -t lab6.clab.yml
docker exec -d clab-$STUDENT-l6-server iperf3 -s
docker exec -d clab-$STUDENT-l6-server python3 -m http.server $((8000 + N))
docker exec -t clab-$STUDENT-l6-odl /opt/odl/bin/client -r 30 -d 5 \
  "feature:install odl-openflowplugin-flow-services-rest odl-openflowplugin-app-table-miss-enforcer"
docker exec -i -e ODL_IP=10.106.$N.100 clab-$STUDENT-l6-sw sh < scripts/sw-setup.sh
./vnfm.sh configure fw1 fw && ./vnfm.sh configure shaper1 shaper
python3 nfvo.py apply vnffg.yaml
```

Клиент Karaf запускается с `-r 30 -d 5`: он сам ждёт, пока Karaf поднимется, вместо `sleep 30`.

## Ход работы и результаты

### Этап 1. NFVI и контроллер

Семь узлов развёрнуты, фичи `odl-openflowplugin-flow-services-rest` и `odl-openflowplugin-app-table-miss-enforcer` в состоянии `Started`. У `sw` `is_connected: true`, `fail_mode: secure`, порты 1–4 и 7–9; 5 и 6 свободны под scale-out. В таблице только table-miss (`cookie=0xa, priority=0, actions=CONTROLLER:65535`). Ping client1 → server — 100% потерь, на client1 `10.7.6.100 INCOMPLETE`, счётчик table-miss вырос с 7 до 9. Логи: [1.1](logs/1.1-deploy.txt), [1.2](logs/1.2-switch.txt), [1.3](logs/1.3-no-chain.txt).

### Этап 2. Дескрипторы, configure

В `fw-vnfd.yaml` указан `provider: "yakovlev"`, создан `shaper-vnfd.yaml`: тип shaper, day-1 конфигурация — команда `tc`, `max_instances: 1`, без `scale_out` в `lcm_operations`. После `vnfm.sh configure`:

- fw1: мост `br0` из `eth1`/`eth2`, IP только на management `eth0`; правила `block tcp/8007`, `allow http`, `allow icmp`, `other`;
- shaper1: `qdisc tbf 8001: root rate 17Mbit burst 16Kb lat 400ms` на `eth2`.

Лог: [logs/2.2-configure.txt](logs/2.2-configure.txt).

### Этап 3. Сервисная цепочка

`nfvo.py apply` — `applied: 24 flows, removed stale: 0`. Проверка ([logs/3.2-check.txt](logs/3.2-check.txt)):

| Проверка | Результат |
| --- | --- |
| ping client1 → server | 3/3, 0% потерь |
| HTTP :80 | `200`, счётчик `allow http` растёт |
| HTTP :8007 | `000` (таймаут), счётчик `block tcp/8007` растёт |
| iperf3 client1 → server (через шейпер) | **16,7 Мбит/с** (receiver) |
| iperf3 server → client1 (`-R`, без шейпера) | **2,07 Гбит/с** |
| client2 ping и HTTP | работают, `pkts` у потоков c2 ненулевые |

### Этап 4. Scale-out

`./vnfm.sh instantiate fw2 fw 5 6` выполняет четыре шага:

1. `docker run --network none --privileged` с метками `nfv-lab=yakovlev-l6`, `vnf-type=fw` — контейнер без сети данных;
2. `containerlab tools veth create` дважды: `fw2:eth1 ↔ sw:eth5` и `fw2:eth2 ↔ sw:eth6`;
3. `attach_port`: `ethtool -K ethX tx off` и `ovs-vsctl add-port br0 ethX -- set interface ethX ofport_request=X`, чтобы номер OpenFlow совпал с номером интерфейса;
4. `configure_vnf`: мост `br0` внутри VNF и правила nftables через `envsubst` (`FW_PORT=8007`).

Затем коммит `lab6: chain c2 -> fw2` и `nfvo.py apply`. Запрос client2 увеличил `allow http` только на fw2 (0 → 6), на fw1 счётчик остался 24; запрос client1 — только на fw1 (24 → 30). Порт 8007 fw2 тоже блокирует. Логи: [4.1](logs/4.1-instantiate.txt), [4.2](logs/4.2-chain-c2-fw2.txt).

### Этап 5. Heal

Хронология ([logs/5-heal.txt](logs/5-heal.txt), время ВМ):

| Время | Событие | Прошло |
| --- | --- | --- |
| 18:14:58 | fw2 создан (scale-out), затем c2 переведена на fw2 | — |
| 18:15:33.465 | **T0**: отказ fw1 (`docker stop`) | 0 |
| 18:15:46.827 | T1: отказ обнаружен вручную: ping client1 100% потерь, client2 работает через fw2 | 13,4 с |
| 18:15:54.227 | T2: в `vnffg.yaml` c1 → `[fw2, shaper1]`, коммит `lab6: heal c1 -> fw2` | +7,4 с |
| 18:15:54.556 | T3: `nfvo.py apply` отправил потоки в ODL | +0,33 с |
| 18:15:54.609 | **T4**: первый успешный ping client1 | +0,05 с |
| 18:15:56.974 | T5: `vnfm.sh terminate fw1 3 4`, порты 3/4 удалены из OVS | +2,4 с |

Время восстановления от отказа до работающего ping — **21,1 с**. Из них сеть перепрограммировалась за 0,38 с (PUT в ODL → FLOW_MOD → OVS), остальные ~21 с — ручное обнаружение и правка YAML. Автоматизировать нужно:

- **обнаружение**: подписка на `PORT_STATUS`/`link-down` в operational-инвентаре ODL или health-check VNFM, а не ручной ping;
- **решение**: резервный экземпляр в VNFFG (`standby: fw2`) и политику, куда переводить цепочки;
- **действие**: `nfvo apply` без участия человека, затем `instantiate` нового экземпляра взамен отказавшего, чтобы вернуть резерв, и `terminate` старого;
- **оповещение** и запись события.

При stateful-FW понадобилась бы ещё синхронизация состояния (conntrackd), иначе после переключения существующие соединения рвутся.

### Этап 6. Производительность

[logs/6.1-perf.txt](logs/6.1-perf.txt):

| Тест | Результат |
| --- | --- |
| `iperf3 -R -P 4 -t 10` (server → client1, без шейпера) | **2,52 Гбит/с** |
| `iperf3 -R` одним потоком | 1,79–2,07 Гбит/с |
| `iperf3 -P 4` (client1 → server, через шейпер) | 16,2 Мбит/с — шейпер ограничивает сумму |
| `ovs-vswitchd` во время нагрузки | **100% CPU** (одно ядро из четырёх, остальное простаивает) |

`top` из задания запускается после окончания iperf3 и показывает простой, поэтому я дополнительно снял `top` во время нагрузки.

## Ответы на вопросы

### 1.3. Почему ping не проходит, хотя клиент и сервер в одной подсети?

«Одна подсеть» означает только, что клиент не ищет маршрутизатор и шлёт ARP-запрос прямо серверу. Связность на L2 даёт коммутатор, а он в режиме `fail-mode=secure` сам не обучается и не рассылает пакеты: пересылает только по потокам. Потоков цепочки ещё нет, есть лишь table-miss, поэтому широковещательный ARP уходит в ODL как packet-in (счётчик 7 → 9). В ODL нет L2-приложения (l2switch не установлен), контроллер пакет не обрабатывает, ARP остаётся `INCOMPLETE`, и до IP дело не доходит.

### 2.1. Какие поля VNFD соответствуют понятиям ETSI SOL001? Чего не хватает?

| Наш VNFD | SOL001 (TOSCA) |
| --- | --- |
| `vdu.resources` (vcpu, memory_mb), `sw_image` | VDU: `tosca.nodes.nfv.Vdu.Compute` с `virtual_compute` и `sw_image_data` |
| `ext_cp` (`cp-in`/`cp-out`, интерфейсы) | внешние точки подключения `VnfExtCp` (и внутренние `VduCp`) |
| `scaling` (min/max) | scaling aspect + `ScalingAspects`, `VduInitialDelta`/`VduScalingAspectDeltas`, instantiation levels |
| `lcm_operations` | интерфейс `Vnflcm`: instantiate, terminate, scale, heal и др. |
| `config` | day-1 конфигурация: LCM-скрипты/`configurable_properties`, у нас — файл nftables или команда tc |
| `id`, `provider`, `version`, `description` | `descriptor_id`, `provider`, `software_version`/`descriptor_version`, `product_name` |

Не хватает: внутренних virtual links и virtual storage; deployment flavours и instantiation levels; правил affinity/anti-affinity (fw1 и fw2 на разных хостах); параметров мониторинга и VNF indicators для автоматического heal и scale; требований к ускорению (`requested_additional_capabilities`: SR-IOV, DPDK, hugepages); `vnfm_info`; упаковки в CSAR с манифестом, контрольными суммами и подписью; TOSCA-импортов и типов.

### 3.1. Почему на каждый переход два потока и почему обратное направление матчится по адресу получателя?

- **IPv4 и ARP.** Поля `ipv4-source`/`ipv4-destination` по правилам prerequisites OpenFlow матчатся только при `ethernet-type 0x0800`. В ARP-пакете нет IPv4-заголовка, его адреса лежат в `arp_spa`/`arp_tpa` при `ethernet-type 0x0806`. Без ARP-потоков клиент не узнает MAC сервера, и IP-трафик не пойдёт вообще.
- **Матч по `in_port`.** Пакет проходит коммутатор несколько раз (из клиента, из FW, из шейпера), а заголовки у него не меняются: VNF прозрачны. Только входной порт показывает, на каком шаге цепочки пакет находится.
- **Обратное направление по получателю.** Цепочка определена по клиенту: c1 — это трафик client1, c2 — трафик client2. В ответах сервера источник у обеих цепочек одинаковый (`10.7.6.100`), различает их только адрес клиента, а он теперь в поле получателя (`nw_dst`, `arp_tpa`). Обратный путь — тот же список портов в обратном порядке, поэтому ответ проходит через те же экземпляры VNF.

### 3.2. Что изменится, если сделать FW stateful (`ct state`), и почему тогда оба направления должны идти через один экземпляр?

Сейчас каждый пакет проверяется сам по себе: отбрасывается всё на порт 8007, остальное пропускается. Stateful-FW ведёт таблицу соединений conntrack и пишет правила вида «новые соединения — только на порт 80, ответы пропускать по `ct state established,related`, остальное — drop». Так ответный трафик пропускается, только если FW видел начало соединения. Для этого экземпляр должен видеть оба направления: SYN в прямом и SYN-ACK в обратном. Если обратный трафик пойдёт через другой экземпляр, у того нет записи conntrack, ответ получит состояние `new`/`invalid` и будет отброшен (или, при разрешающей политике, правило перестанет что-либо фильтровать). Поэтому нужна симметричная маршрутизация. В `nfvo.py` она обеспечена построением: обратный путь — зеркальный прямому. При переключении на другой экземпляр (heal) установленные соединения теряются без синхронизации состояния.

### 4.2. Почему балансировка группой OpenFlow `select` опасна для stateful-VNF?

Группа `select` выбирает bucket по хешу полей пакета. Хеш прямого и обратного направлений разный (источник и получатель меняются местами), поэтому ответ может уйти в другой экземпляр, у которого нет состояния соединения. При изменении числа buckets (scale-out, отказ) хеши перераспределяются, и уже установленные соединения переезжают на другой FW и рвутся. Фрагменты без L4-заголовка хешируются иначе, чем первый фрагмент. Наша политика по источнику (весь трафик клиента — через один FW в обе стороны) этих проблем не имеет. Для балансировки stateful-VNF нужен симметричный и согласованный хеш (например `symmetric_l3l4`), привязка сессий или синхронизация состояния между экземплярами.

### 6.1. Где узкое место в нашей NFVI и какие технологии его решают?

Узкое место — `ovs-vswitchd` с datapath `netdev`: под нагрузкой он занимает 100% одного ядра, а остальные три простаивают. Один поток читает и пишет пакеты через AF_PACKET: на каждый пакет приходятся системные вызовы и копирование ядро ↔ userspace. Пакет цепочки проходит коммутатор три раза в каждую сторону, а каждая VNF добавляет ещё два перехода через ядро (veth → мост `br0` → veth). Отсюда потолок около 2,5 Гбит/с.

| Технология | Что даёт | Чем расплачиваемся |
| --- | --- | --- |
| DPDK | poll-mode драйверы в userspace, обход ядра, без прерываний и копирований | выделенные ядра, которые крутятся на 100% даже без трафика; hugepages; NUMA-привязка; нет привычных инструментов ядра |
| OVS-DPDK | тот же OVS с PMD-потоками, несколько очередей → масштабируется на ядра | то же, плюс сложнее настройка и отладка |
| vhost-user | VNF (ВМ) ↔ OVS-DPDK через разделяемую память virtio, без ядра хоста | нужны hugepages и DPDK внутри или virtio-net в госте; сложнее миграция |
| SR-IOV | VF сетевой карты напрямую в VNF, vSwitch обходится полностью | теряется гибкость: цепочки нельзя строить в vSwitch, нужен коммутатор в NIC/ToR; ограниченное число VF; трудна живая миграция |
| SmartNIC / аппаратная разгрузка OVS (TC flower, rte_flow) | datapath в железе, CPU хоста свободен | стоимость, привязка к вендору, не все действия разгружаются |

Общий принцип: скорость покупается выделенными ресурсами (ядра, память), специализированным железом и потерей гибкости программного datapath.

## Проблема и решение: шейпер пропускал 0 бит/с

Первый прямой iperf3 показал 0 бит/с, хотя ping и HTTP проходили ([logs/3.2-shaper-mtu-issue.txt](logs/3.2-shaper-mtu-issue.txt)). containerlab создаёт veth с MTU 9500, клиент шлёт кадры по 9514 байт, а в `vnfm.sh` у tbf стояло `burst 32kbit`, то есть 4 КБ. Кадр больше ведра tbf никогда не пропускает: счётчик `dropped` рос, TCP уходил в повторы. Маленькие пакеты (ping, HTTP GET) проходили, обратное направление не шейпится.

Исправление: `burst 16kb` в `vnfm.sh` и в `shaper-vnfd.yaml` (по `man tc-tbf` burst должен быть не меньше MTU). Скорость 17 Мбит/с не изменилась, топология и MTU тоже. После исправления прямое направление даёт 16,7 Мбит/с.

## Финальный vnffg.yaml

Обе цепочки идут через fw2 ([vnffg.yaml](vnffg.yaml)):

```yaml
chains:
  - {name: "${STUDENT}-c1", from: client1, to: server, path: [fw2, shaper1]}
  - {name: "${STUDENT}-c2", from: client2, to: server, path: [fw2, shaper1]}
```

История в Git: `lab6: chain c2 -> fw2`, `lab6: heal c1 -> fw2`.

## Финальный артефакт

[logs/7-artifact.txt](logs/7-artifact.txt): экземпляры fw2 и shaper1 (fw1 удалён), потоки `sfc-yakovlev-c1-…` с ненулевыми `pkts`, счётчики fw2 с правилом `block tcp/8007`, `client1 HTTP: 200`, iperf3 16,8 Мбит/с, `igoryakovlev@colima`, 16.11.2026 18:16:48.
