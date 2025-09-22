import {
  Wallet,
  Provider,
  WalletUnlocked,
  ContractFactory,
  hexlify,
  Contract,
} from 'fuels';
import fs from 'fs-extra';
import dotenv from 'dotenv';

dotenv.config();

async function main() {
  try {
    const provider = await new Provider(
      'https://testnet.fuel.network/v1/graphql',
    );
    const protocolDeployer = process.env.PROTOCOL_DEPLOYER!;
    const protocolDeployerWallet: WalletUnlocked =
      Wallet.fromMnemonic(protocolDeployer);
    console.log(`Protocol Deployer Address: ${protocolDeployerWallet.address}`);
    console.log(
      `-------------------------------------------------------------`,
    );

    protocolDeployerWallet.connect(provider);

    const bytecode = fs.readFileSync('./out/debug/axios-fuel-core.bin');
    const bytecodeHex = hexlify(bytecode);

    const abi = fs.readJsonSync('./out/debug/axios-fuel-core-abi.json');
    const factory = new ContractFactory(
      bytecodeHex,
      abi,
      protocolDeployerWallet,
    );

    const protocolOwner = process.env.PROTOCOL_OWNER!;
    const protocolOwnerWallet: WalletUnlocked =
      Wallet.fromMnemonic(protocolOwner);
    console.log(`Protocol Onwer Address: ${protocolOwnerWallet.address}`);
    console.log(
      `-------------------------------------------------------------`,
    );

    factory.setConfigurableConstants({
      PROTOCOL_OWNER: { bits: protocolOwnerWallet.address.toB256() },
    });

    const tx = await factory.deploy();
    const response = await tx.waitForResult();
    console.log('Contract Id: ', response.contract.id.toString());
    console.log(
      `-------------------------------------------------------------`,
    );
    const protocolAdminWallet = getProtocolAdminWallet();
    console.log(`Protocol Admin Wallet: ${protocolAdminWallet.address}`);
    await addProtocolAdmin(
      response.contract,
      getProtocolAdminWallet(),
      protocolOwnerWallet,
    );
    await updateProtocolConfigByAdmin(
      response.contract,
      getProtocolAdminWallet(),
    );
  } catch (error) {
    console.error(error);
  }
}

async function addProtocolAdmin(
  contract: Contract,
  protocolAdminWallet: WalletUnlocked,
  protocolOwnerWallet: WalletUnlocked,
) {
  contract.account = protocolOwnerWallet;
  const provider = await getProviderForTestnet();
  protocolOwnerWallet.connect(provider);
  const tx = await contract.functions
    .add_admin({
      bits: protocolAdminWallet.address.toB256(),
    })
    .call();
  console.log(
    '---------------------------------------debug----------------------------------',
  );
}
async function updateProtocolConfigByAdmin(
  contract: Contract,
  protocolAdminWallet: WalletUnlocked,
) {
  contract.account = protocolAdminWallet;
  const provider = await getProviderForTestnet();
  protocolAdminWallet.connect(provider);
  console.log(`printf:1`);
  const tx = await contract.functions
    .update_protocol_config({
      protocol_fee_receiver: { bits: protocolAdminWallet.address.toB256() },
      protocol_fee: 100,
      protocol_liquidation_fee: 100,
      liquidator_fee: 100,
      time_request_loan_expires: 28800,
      oracle_max_stale: 30,
      min_loan_duration: 600,
    })
    .call();
  console.log(tx);
}
function getContractFactory(wallet: WalletUnlocked): ContractFactory<Contract> {
  const bytecode = fs.readFileSync('./out/debug/axios-fuel-core.bin');
  const bytecodeHex = hexlify(bytecode);

  const abi = fs.readJsonSync('./out/debug/axios-fuel-core-abi.json');
  const factory = new ContractFactory(bytecodeHex, abi, wallet);
  return factory;
}

async function getProviderForTestnet(): Promise<Provider> {
  const provider = await new Provider(
    'https://testnet.fuel.network/v1/graphql',
  );
  return provider;
}

function getProtocolDeployerWallet(): WalletUnlocked {
  const protocolDeployer = process.env.PROTOCOL_DEPLOYER!;
  const protocolDeployerWallet: WalletUnlocked =
    Wallet.fromMnemonic(protocolDeployer);
  return protocolDeployerWallet;
}

function getProtocolOwnerWallet(): WalletUnlocked {
  const protocolOwner = process.env.PROTOCOL_OWNER!;
  const protocolOwnerWallet: WalletUnlocked =
    Wallet.fromMnemonic(protocolOwner);
  return protocolOwnerWallet;
}

function getProtocolAdminWallet(): WalletUnlocked {
  const protocolAdmin = process.env.PROTOCOL_ADMIN!;
  const protocolAdminWallet: WalletUnlocked =
    Wallet.fromMnemonic(protocolAdmin);
  return protocolAdminWallet;
}

main();
