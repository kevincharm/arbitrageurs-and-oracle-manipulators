# ACHTUNG: The build context should be the project root!
FROM centos:7

# Basic deps
RUN yum install -y epel-release && \
    yum groupinstall -y 'Development Tools'

# Install node
RUN curl --silent --location https://rpm.nodesource.com/setup_14.x | bash - && \
    yum install -y nodejs && \
    node --version

# Install yarn
RUN curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo && \
    yum install -y yarn && \
    yarn --version

WORKDIR /app
# Copy source && install dependencies && build
COPY . .
RUN cd /app && \
    yarn install && \
    yarn build

CMD ["yarn", "hardhat", "test"]
