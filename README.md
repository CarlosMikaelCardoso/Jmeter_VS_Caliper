# API-Driven Performance Testing Framework for Hyperledger Besu

Welcome to the **Jmeter_VS_Caliper project!** This repository contains the framework presented in the paper "An API-Driven Framework for Performance Testing of Hyperledger Besu Blockchain Networks".

The goal of this project is to provide a solution for realistic performance testing on **Hyperledger Besu networks** , bridging the gap between protocol-level benchmarks (like Hyperledger Caliper) and real-world application performance. The approach is API-centric, simulating how real applications interact with the blockchain.

- **Black-Box Testing via JMeter:** Utilizes Apache JMeter to simulate user traffic and measure performance from the application's perspective (Application-Centric) , focusing on metrics like transaction acceptance latency.
- **Intelligent API:** The core of the solution is a custom API that includes:
   - **Atomic Nonce Management:** Ensures concurrent transactions do not fail.
   - **Dynamic Load Balancing:** Distributes the load evenly across Besu nodes to prevent bottlenecks.
- **Decoupled Architecture:** The framework operates with separate VMs for JMeter and the Besu network (including the API and nodes) to simulate a production environment.
- **Orchestration with Docker:** Uses Docker to manage the Besu network components, the API, Workload Modules, and metrics collection.
- **Comparative Analysis:** The setup allows for a direct comparison between the light load of a protocol-centric test (Caliper) and the uniform stress load of an application-centric test (JMeter + API).
- **Operational System**: Ubuntu Server 24.04 LTS

## Requirements

The requirements are installed automatically by the `setup_besu_networks.sh` script, but it is important to ensure you have the following prerequisites (cURL, wget, tar):

- **Java JDK 17+**
- **Besu v24.7.0+**
- **Docker & Docker-Compose**
- **cURL, wget, tar**

## Installation and Setup

Follow the steps below to set up the project on your machine:

1. Clone these repositories:
   ```bash
   git clone https://github.com/CarlosMikaelCardoso/Jmeter_VS_Caliper.git
   git clone https://github.com/hyperledger-caliper/caliper-benchmarks.git
   cd caliper-benchmarks
   git checkout v0.6.0
   ```
   1.2 Configuration of nodes:
      ```bash
      Go to ./Jmeter_VS_Caliper/update-docker-compose.py and change the 22 and 24 (<your IP>) by your IP address
      Now go to ./Jmeter_VS_Caliper/testes/networkconfig.json --> Line 6: Change <your IP> to your IP address
      And finally got to ./Jmeter_VS_Caliper/testes/5_Users/caliper/simple/config.yaml --> line 54: Change <YourIP> to your IP address
      ```
2. Execute the network setup script. It will prepare all the necessary files for the nodes.
   ```bash
   sudo chmod +x setup_besu_networks.sh
   ./setup_besu_networks.sh
   ```

## Testing with Caliper and JMeter

### If you want to compare the performance of the two, it's recommended to run Caliper first, as it deploys the contract that JMeter will use for its tests.
In the `testes` folder, edit the "url" in `networkconfig.json` and set the machine's IP address.

# Caliper
```bash
cd testes
sudo chmod +x run_caliper.sh
./run_caliper.sh <number of users> <number of repetitions>
```
By default, Caliper runs the test once with 5 Workers.

# JMeter
For JMeter, we need to run the API so it can perform the operations.

```bash
cd api-besu
npm install # Installs the API dependencies
# Export the necessary environment variables for the Besu configuration.
export DEPLOYER_PRIVATE_KEY="0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
export CONTRACT_ADDRESS="<contract_address>" # This address is located in /testes/contract_address.txt
node api_load_balancer
```

## How API Works![arquiteture2](https://github.com/user-attachments/assets/2026c77a-cc63-466b-894e-99354ba572df)


In another terminal:

```bash
cd Jmeter_VS_Caliper/testes
sudo chmod +x run_jmeter_api.sh
./run_jmeter_api.sh <number of users> <number of repetitions>
```
By default, JMeter runs the test once with 5 Threads.

At the end of each `.sh` script execution, a folder is generated containing log files and test results.
You can modify the Caliper configuration file - `5_Users/caliper/simple/config.yaml` - to define the number of Workers and the number of transactions to be performed. Similarly, for JMeter, you can modify the JMX files - `5_users/jmeter/*.jmx` - which are split into three separate files for each operation (Open, Query, and Transfer).

## Contribution

Contributions are welcome! Follow the steps below to contribute:

1. Fork the repository.
2. Create a branch for your feature/bugfix:
   ```bash
   git checkout -b my-feature
   ```
3. Commit your changes:
   ```bash
   git commit -m "feat: My new feature"
   ```
4. Push to the branch:
   ```bash
   git push origin my-feature
   ```
5. Open a Pull Request.

## Contact

If you have questions or suggestions, get in touch:

- **Developer:** Carlos Mikael Cardoso Da Costa
- **Email:** mikael.cardoso.costa13@gmail.com

## License

This project is licensed under the [MIT License](LICENSE).

---

Thank you for using this project!
