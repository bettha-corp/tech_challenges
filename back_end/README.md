# Bettha Back-End Engineer Challenge

***Nota: Utilizaremos os seguintes critérios para a avaliação: Desempenho, Testes, Manutenabilidade e boas práticas de engenharia de software.***

1.- Sua squad irá desenvolver uma nova funcionalidade que irá prover um serviço de validação de cadastro de clientes, ao informar o CNPJ e o CEP do endereço do cliente iremos consultar duas APIs de terceiros, a primeira irá retornar informações da empresa de acordo com o CNPJ e a segunda API irá retornar detalhes de um endereço a partir de um CEP. Com os resultados das duas APIs iremos comparar o endereço do cadastro da empresa obtido pelo CNPJ com o endereço obtido através da consulta do CEP e verificar se as informações de unidade federativa, cidade e logradouro coincidem, e caso o endereço de uma consulta seja encontrada na outra retornaremos HTTP 200 e na negativa um HTTP 404.
Como este novo serviço deverá ser resiliente e essencial para os nossos cadastros, a solução proposta deverá permitir retentativas automáticas em casos de falhas e o chaveamento entre dois provedores de resolução do endereço pelo CEP, ou seja usaremos a API de um provedor como padrão e caso o serviço esteja fora do ar o serviço proposto deverá chamar o segundo provedor automaticamente após "N" tentativas.
Apesar de depender diretamente do consumo de múltiplas APIs de terceiros a resposta do serviço desenvolvido deverá ser síncrono.
Você pode verificar exemplos das APIs utilizadas em [requests_e_responses_apis_questao_1.json](https://github.com/bettha-corp/tech-challenges/blobrequests_e_responses_apis_questao_1.json).
Descreva e detalhe como você implementaria o referido serviço? Não é necessário desenvolver o código a menos que você julgue necessário. Sinta-se a vontade para utilizar diagramas, desenhos, descrição textual, arquitetura, design patterns, etc.

2.- Foi nos solicitado a criação de um relatório que mostre a utilização do serviço de lançamentos de foguetes separados por cada um dos nossos clientes em um intervalo de 30 dias. A nossa proposta para o desenvolvimento deste relatório é o de tentar evitar ao máximo algum impacto no fluxo de execução deste endpoint/api (de lançamento de foguetes), uma vez que este é o principal produto da empresa. 
Com essas premissas em mente, o time propôs a utilização apenas das solicitações/requests em comum com o atual serviço e armazenar os dados necessários para o relatório utilizando uma base de dados paralela à base de dados do serviço de lançamentos.
Como você atenderia essa demanda? Lembre-se, caso o novo workflow proposto para o armazenamento dos dados dos relatórios falhe, ele não deve impactar no serviço de lançamentos. 
Descreva em detalhes como você implementaria a solução. Sinta-se a vontade para utilizar diagramas, desenhos, descrição textual, arquitetura, design patterns, etc.

```ruby
# Linguagem: Ruby

require 'securerandom'
require 'dry-container'
require 'dry-auto_inject'

class Container
  extend Dry::Container::Mixin

  register(:claims_service) { ClaimsService.new }
  register(:jwt_service) { JwtService.new }
  register(:launch_service) { LaunchService.new }
end

Inject = Dry::AutoInject(Container)

class RocketsController < ApplicationController
  include Inject[:claims_service, :jwt_service, :launch_service]

  before_action :authenticate!

  def launch
    trace_id = request.headers['trace_id'] || SecureRandom.uuid
    schema = launch_params

    raise ActionController::BadRequest, 'where is the request payload?' unless schema.present?

    unless RulesEngine.launch_approved?(schema)
      render json: { error: 'your launch is not allowed.' }, status: :method_not_allowed and return
    end

    pre_flight = launch_service.pre_flight_check

    unless RulesEngine.pre_flight_status_ok?(pre_flight.status)
      render json: { error: 'your launch is compromised, please abort.' }, status: :internal_server_error and return
    end

    countdown_status = launch_service.countdown

    render json: launch_service.launch(
      trace_id: trace_id,
      customer_id: schema[:customer_id],
      countdown_status: countdown_status,
      pre_flight: pre_flight
    )
  rescue StandardError => e
    render json: { error: "Error during launch... #{e.message}" }, status: :internal_server_error
  end

  private

  def authenticate!
    auth_adapter = AuthAdapter.new(claims_service: claims_service, jwt_service: jwt_service)
    unless auth_adapter.authenticate(request)
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end

  def launch_params
    params.permit(:customer_id)
  end
end
```

3.- Para evitar sobrecargas em serviços de terceiros, nossa squad decidiu implementar um agendador de eventos para ser utilizado durante a verificação do status de execução de uma operação de reenderização de vídeos em um dos nossos workflows orquestrados utilizando kafka. Como o kafka não permite o agendamento de eventos, a squad acabou por desenvolver um agendador próprio que armazena o evento temporariamente em um banco de dados do tipo chave/valor em memória, bem como um processo executará consultas (em looping) por eventos enfileirados no banco chave/valor que estão com o agendamento para vencer. Ao encontrar um, este agendamento é transformado em um novo evento em um tópico do kafka para dar continuidade ao workflow temporariamente paralizado pelo agendamento e finalmente removido do banco de agendamentos. Confome ilustrado no diagrama [event_scheduler.png](https://github.com/bettha-corp/tech-challenges/event_scheduler.png).
Como o referido workflow deverá ser resiliente e essencial para o nosso produto, a squad gostaria de garantir que o serviço conseguirá suportar 1.000 requesições por segundo com o P99 de 30ms de latencia nas requisições. Descreva detalhadamente quais testes você desenvolveria e executaria para garantir as premissas? Como você faria/executaria os testes propostos?

```ruby
# Linguagem: Ruby

require 'sidekiq-scheduler'
para processar a tarefa
class SchedulerController < ApplicationController
  before_action :authenticate!

  def schedule
    raise ActionController::BadRequest, 'where is the request payload?' unless params[:event_content].present? && params[:scheduler_datetime].present?

    begin
      SchedulerWorker.perform_at(params[:scheduler_datetime].to_time, params[:event_content])

      render json: { message: 'Event scheduled successfully' }, status: :ok
    rescue StandardError => e
      render json: { error: "Error during scheduler event... #{e.message}" }, status: :internal_server_error
    end
  end

  private

  def authenticate!
    auth_adapter = AuthAdapter.new(
      claims_service: Container.resolve(:claims_service),
      jwt_service: Container.resolve(:jwt_service)
    )

    unless auth_adapter.authenticate(request)
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end

# Worker to process task
class SchedulerWorker
  include Sidekiq::Worker

  def perform(event_content)
    EventPublisher.publish(event_content)
  end
end
```

4.- ATENÇÃO: Caso você tenha escrito o código para responder a questão 1, por favor desconsiderar a questão 5 e nos encaminhe o código da questão 1 no lugar.
 Tomando como base a estrutura do banco de dados fornecida (conforme diagrama [ER_diagram.png](https://github.com/bettha-corp/tech-challenges/tech-challenges/ER_diagram.png) e/ou script DDL [1_create_database_ddl.sql](https://github.com/bettha-corp/tech-challenges/1_create_database_ddl.sql), disponibilizados no repositório do github) construa uma API REST em Ruby on Rails que irá criar um usuário. Os campos obrigatórios serão nome, e-mail e papel do usuário. A senha será um campo opcional, caso o usuário não informe uma senha o serviço da API deverá gerar essa senha automaticamente.

5.- Ajude-nos fazendo o ‘Code Review’ do código de um robô/rotina que exporta os dados da tabela “users” de tempos em tempos. O código foi disponibilizado no mesmo repositório do git hub dentro da pasta [bot](https://github.com/bettha-corp/tech-challenges/bot/bot.rb). ***ATENÇÃO: Não é necessário implementar as revisões, basta apenas anota-las em um arquivo texto ou em forma de comentários no código.***

6.- Qual ou quais Padrões de Projeto/Design Patterns você utilizaria para normalizar serviços de terceiros (tornar múltiplas interfaces de diferentes fornecedores uniforme), por exemplo serviços de disparos de e-mails, ou então disparos de SMS. ***ATENÇÃO: Não é necessário implementar o Design Pattern, basta descrever qual você utilizaria e por quais motivos optou pelo mesmo.***

BOA SORTE!