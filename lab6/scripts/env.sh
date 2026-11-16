# Окружение ЛР6. Подключать из каталога lab6: source scripts/env.sh
export STUDENT=yakovlev N=7
export ODL=http://10.106.$N.100:8181
odl_get() { curl -s -u admin:admin "$ODL/rests/data/$1" | jq .; }
# Нет containerlab на хосте (Colima на Mac) — запускаем официальный образ.
# export -f нужен, чтобы функцию видел vnfm.sh (containerlab tools veth create).
if ! command -v containerlab >/dev/null; then
  containerlab() {
    docker run --rm --privileged --network host --pid host -e STUDENT -e N \
      -v /var/run/docker.sock:/var/run/docker.sock -v /var/run/netns:/var/run/netns \
      -v /etc/hosts:/etc/hosts -v /var/lib/docker/containers:/var/lib/docker/containers \
      -v "$PWD":"$PWD" -w "$PWD" ghcr.io/srl-labs/clab:latest containerlab "$@"
  }
  export -f containerlab
fi
