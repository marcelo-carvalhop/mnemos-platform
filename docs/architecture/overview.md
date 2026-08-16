# Visão de arquitetura

Mnemos utiliza três classes de cliente sobre contratos comuns: aplicativo móvel, futura aplicação web e terminal físico. Mobile e web consomem o backend; o terminal pode ser provisionado pelo mobile e, depois, sincronizar diretamente com o backend pela rede de infraestrutura.

O diretório `spec/` define os objetos interoperáveis. As estruturas internas do Drift/SQLite, do banco do backend ou da memória do firmware não são parte do protocolo público.

```text
                 Backend Mnemos
                 /           \
                /             \
          Mobile               Web
             \
              \\ provisionamento temporário
               \
              Terminal ───── sincronização direta ───── Backend
```
