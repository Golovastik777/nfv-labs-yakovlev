# ЛР6: команды для скриншотов

14 скриншотов. Сценарий проходит лабу заново, с чистого стенда, по порядку этапов: только так на скриншотах будут промежуточные состояния (ping до цепочки, fw1, scale-out при c1 на fw1). После последнего скриншота стенд оказывается в итоговом состоянии: fw1 удалён, обе цепочки идут через fw2.

Каждый блок вставляется в терминал целиком. Скрин снимается после того, как вывод закончился. Перед каждым блоком очищайте экран через `Ctrl+L`, тогда на скрине будут и команды, и вывод.

Все значения подставлены: `yakovlev`, `N = 7`, порт `8007`, хосты `10.7.6.x`, ODL `10.106.7.100`. Промежуточные версии `vnffg.yaml` создаются во временных файлах `/tmp/vnffg-*.yaml`, сам `vnffg.yaml` в репозитории не меняется (его история — в коммитах `lab6: chain c2 -> fw2` и `lab6: heal c1 -> fw2`).

## Подготовка (без скриншотов, ≈3 минуты)

Терминал пошире и повыше. Войдите в ВМ и перейдите в каталог лабы:

```bash
colima ssh
```

```bash
cd ~/nfv-labs-yakovlev/lab6 && source scripts/env.sh
```

`source scripts/env.sh` обязателен: он задаёт `STUDENT` и `N` для `nfvo.py` и `vnfm.sh` и подключает обёртку `containerlab`.

Сброс стенда. fw2 удаляется отдельно: его создал `vnfm.sh`, в топологию он не входит, и `destroy` его не тронет.

```bash
docker rm -f clab-yakovlev-l6-fw2; containerlab destroy -t lab6.clab.yml --cleanup
```

```bash
containerlab deploy -t lab6.clab.yml
```

Промежуточные версии VNFFG:

```bash
sed 's/path: \[fw2, shaper1\]/path: [fw1, shaper1]/' vnffg.yaml > /tmp/vnffg-1.yaml && sed '/-c1"/s/path: \[fw2, shaper1\]/path: [fw1, shaper1]/' vnffg.yaml > /tmp/vnffg-2.yaml && grep path /tmp/vnffg-1.yaml /tmp/vnffg-2.yaml
```

Ожидается: в `vnffg-1` обе цепочки через `[fw1, shaper1]`, в `vnffg-2` c1 через fw1, c2 через fw2.

## Соответствие требованиям

| Скрин | Что показывает | Требование к защите / этап |
| --- | --- | --- |
| 1 | узлы, серверы на server, фичи ODL | этап 1.1–1.2 |
| 2 | настройка OVS, `ovs-vsctl show`, контроллер подключён | защита п.1 |
| 3 | ping до применения цепочки | защита п.1, вопрос 1.3 |
| 4 | configure fw1 и shaper1, `nft list ruleset`, `tc qdisc show` | защита п.2 |
| 5 | дескрипторы `shaper-vnfd.yaml` и `fw-vnfd.yaml` | защита п.2 |
| 6 | `nfvo.py apply`, `dump-flows` цепочки c1 | защита п.3 |
| 7 | ping, HTTP 200, блокировка 8007, счётчики FW | защита п.4 |
| 8 | iperf3 в обе стороны, `nfvo.py show` | защита п.4 |
| 9 | scale-out: instantiate fw2, порты 5/6 | защита п.5 |
| 10 | c2 → fw2: счётчик растёт только на fw2 | защита п.5 |
| 11 | heal: отказ fw1 и восстановление со временем | защита п.6 |
| 12 | terminate fw1, `vnfm.sh list` | защита п.6 |
| 13 | производительность: iperf3 `-P 4`, `top` под нагрузкой | этап 6 |
| 14 | финальный артефакт | этап 7 |

---

## Скрин 1. Узлы, серверы, фичи ODL

```bash
containerlab inspect -t lab6.clab.yml
docker exec -d clab-yakovlev-l6-server iperf3 -s
docker exec -d clab-yakovlev-l6-server python3 -m http.server 8007
docker exec -t clab-yakovlev-l6-odl /opt/odl/bin/client -r 30 -d 5 "feature:install odl-openflowplugin-flow-services-rest odl-openflowplugin-app-table-miss-enforcer"
docker exec -t clab-yakovlev-l6-odl /opt/odl/bin/client "feature:list -i" | grep -E "openflowplugin-flow-services-rest|table-miss"
```

Ожидается: семь узлов `running`, две фичи `Started`. Установка фич ждёт запуска Karaf, это до минуты.

## Скрин 2. Коммутатор подключён к контроллеру

```bash
docker exec -i -e ODL_IP=10.106.7.100 clab-yakovlev-l6-sw sh < scripts/sw-setup.sh
sleep 20
docker exec clab-yakovlev-l6-sw ovs-vsctl show | head -6
docker exec clab-yakovlev-l6-sw ovs-ofctl -O OpenFlow13 dump-flows br0
```

Ожидается: порты 1–4 и 7–9, `Controller "tcp:10.106.7.100:6653"`, `is_connected: true`, `fail_mode: secure`, единственный поток table-miss.

## Скрин 3. Без цепочки связи нет

```bash
docker exec clab-yakovlev-l6-client1 ping -c 2 -W 1 10.7.6.100
docker exec clab-yakovlev-l6-client1 ip neigh
docker exec clab-yakovlev-l6-sw ovs-ofctl -O OpenFlow13 dump-flows br0
```

Ожидается: `100% packet loss`, `10.7.6.100 INCOMPLETE`, счётчик table-miss вырос.

## Скрин 4. Configure VNF

```bash
./vnfm.sh configure fw1 fw > /dev/null
./vnfm.sh configure shaper1 shaper > /dev/null
./vnfm.sh list
docker exec clab-yakovlev-l6-fw1 nft list ruleset
docker exec clab-yakovlev-l6-shaper1 tc qdisc show dev eth2
docker exec clab-yakovlev-l6-fw1 ip -br link show master br0
```

Ожидается: правила `block tcp/8007`, `allow http`, `allow icmp`, `other`; `tbf … rate 17Mbit burst 16Kb`; в мосте `br0` fw1 — `eth1` и `eth2`.

## Скрин 5. Дескрипторы

```bash
cat descriptors/shaper-vnfd.yaml
cat descriptors/fw-vnfd.yaml
```

## Скрин 6. Применение VNFFG и потоки цепочки c1

```bash
grep path /tmp/vnffg-1.yaml
python3 nfvo.py apply /tmp/vnffg-1.yaml
docker exec clab-yakovlev-l6-sw ovs-ofctl -O OpenFlow13 dump-flows br0 | grep "priority=300" | grep 10.7.6.11
```

Ожидается: `applied: 24 flows`, 12 потоков c1: прямое направление по `nw_src`/`arp_spa=10.7.6.11` (1→3, 4→7, 8→9), обратное по `nw_dst`/`arp_tpa=10.7.6.11` (9→8, 7→4, 3→1).

## Скрин 7. Связность, HTTP и межсетевой экран

```bash
docker exec clab-yakovlev-l6-client1 ping -c 3 10.7.6.100
docker exec clab-yakovlev-l6-client1 curl -s -o /dev/null -w "%{http_code}\n" http://10.7.6.100/
docker exec clab-yakovlev-l6-client1 curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://10.7.6.100:8007/
docker exec clab-yakovlev-l6-fw1 nft list ruleset | grep counter
```

Ожидается: ping 0% потерь, `200`, `000` (через 3 секунды), счётчик `block tcp/8007` ненулевой.

## Скрин 8. Шейпер: iperf3 в обе стороны

```bash
docker exec clab-yakovlev-l6-client1 iperf3 -c 10.7.6.100 -t 5 | tail -4
docker exec clab-yakovlev-l6-client1 iperf3 -c 10.7.6.100 -t 5 -R | tail -4
python3 nfvo.py show vnffg.yaml | grep c1
```

Ожидается: в прямом направлении около 17 Мбит/с (строка `receiver`), в обратном — порядка 2 Гбит/с; `pkts` у потоков c1 ненулевые.

## Скрин 9. Scale-out: второй экземпляр FW

```bash
./vnfm.sh instantiate fw2 fw 5 6 | grep -E "Created link|создан"
./vnfm.sh list
docker exec clab-yakovlev-l6-sw ovs-ofctl -O OpenFlow13 show br0 | grep -E "^ [56]\("
docker exec clab-yakovlev-l6-fw2 nft list ruleset | grep counter
```

Ожидается: два канала `fw2:eth1 — sw:eth5` и `fw2:eth2 — sw:eth6`, fw2 в списке с типом `fw`, порты 5 и 6 в OVS, правила fw2 с нулевыми счётчиками.

## Скрин 10. Цепочка c2 на fw2

```bash
grep path /tmp/vnffg-2.yaml
python3 nfvo.py apply /tmp/vnffg-2.yaml
docker exec clab-yakovlev-l6-client2 curl -s -o /dev/null -w "client2: %{http_code}\n" http://10.7.6.100/
docker exec clab-yakovlev-l6-fw2 nft list ruleset | grep "allow http"
docker exec clab-yakovlev-l6-fw1 nft list ruleset | grep "allow http"
docker exec clab-yakovlev-l6-client1 curl -s -o /dev/null -w "client1: %{http_code}\n" http://10.7.6.100/
docker exec clab-yakovlev-l6-fw2 nft list ruleset | grep "allow http"
docker exec clab-yakovlev-l6-fw1 nft list ruleset | grep "allow http"
docker exec clab-yakovlev-l6-client2 curl -s -m 3 -o /dev/null -w "client2 :8007: %{http_code}\n" http://10.7.6.100:8007/
docker exec clab-yakovlev-l6-fw2 nft list ruleset | grep "block"
```

Ожидается: после запроса client2 счётчик `allow http` на fw2 равен 6, на fw1 не меняется; после запроса client1 растёт только fw1, fw2 остаётся 6. Порт 8007 fw2 тоже блокирует (`000`, счётчик `block` 3).

## Скрин 11. Heal: отказ fw1 и восстановление

```bash
date +%T.%3N; docker stop clab-yakovlev-l6-fw1
docker exec clab-yakovlev-l6-client1 ping -c 2 -W 1 10.7.6.100
docker exec clab-yakovlev-l6-client2 ping -c 2 10.7.6.100
grep path vnffg.yaml
date +%T.%3N; python3 nfvo.py apply vnffg.yaml
until docker exec clab-yakovlev-l6-client1 ping -c 1 -W 1 10.7.6.100 > /dev/null; do :; done; date +%T.%3N
docker exec clab-yakovlev-l6-client1 ping -c 2 10.7.6.100
```

Ожидается: c1 — 100% потерь, c2 работает через fw2; финальный `vnffg.yaml` (обе цепочки через fw2) применяется, и ping client1 восстанавливается через доли секунды после `apply`. Три метки времени: отказ, применение, первый успешный ping.

## Скрин 12. Terminate fw1

```bash
./vnfm.sh terminate fw1 3 4
./vnfm.sh list
docker exec clab-yakovlev-l6-sw ovs-ofctl -O OpenFlow13 show br0 | grep -E "^ [0-9]+\("
docker exec clab-yakovlev-l6-client1 curl -s -o /dev/null -w "client1: %{http_code}\n" http://10.7.6.100/
```

Ожидается: fw1 нет в списке, портов 3 и 4 нет в OVS, client1 получает `200` через fw2.

## Скрин 13. Производительность

```bash
docker exec clab-yakovlev-l6-client1 iperf3 -c 10.7.6.100 -t 10 -R -P 4 | grep -E "SUM.*(sender|receiver)"
docker exec -d clab-yakovlev-l6-client1 iperf3 -c 10.7.6.100 -t 8 -R -P 4; sleep 4; docker exec clab-yakovlev-l6-sw sh -c "top -b -n 1 | head -12"; sleep 6
```

Ожидается: суммарно 2,5–3,5 Гбит/с; во время нагрузки `ovs-vswitchd` около 100% CPU (одно ядро). `sleep 6` в конце ждёт, пока закончится фоновый iperf3, иначе в артефакте iperf3 ответит `server is busy`.

## Скрин 14. Финальный артефакт

```bash
echo "========================================" && \
echo "ЛР6 завершена: $(date '+%d.%m.%Y %H:%M:%S')" && \
echo "Студент: $(whoami)@$(hostname), STUDENT=yakovlev, N=7" && \
echo "========================================" && \
./vnfm.sh list && \
python3 nfvo.py show vnffg.yaml | head -12 && \
docker exec clab-yakovlev-l6-fw2 nft list ruleset | grep counter && \
docker exec clab-yakovlev-l6-client1 curl -s -o /dev/null -w "client1 HTTP: %{http_code}\n" http://10.7.6.100/ && \
docker exec clab-yakovlev-l6-client1 iperf3 -c 10.7.6.100 -t 3 | tail -3
```

Ожидается: fw2 и shaper1 без fw1, потоки `sfc-yakovlev-c1-…` с ненулевыми `pkts`, правило `block tcp/8007` на fw2, `client1 HTTP: 200`, около 17 Мбит/с, логин, хост и время.

Скриншоты пришлите в чат по порядку, номер — в имени файла или подписи.
