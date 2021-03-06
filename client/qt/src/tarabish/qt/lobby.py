from PySide import QtCore
from PySide.QtCore import Qt, QTimer
from PySide.QtGui import *
from tarabish.thrift.ttypes import InvalidOperation, EventType
from table import Table

class TableSeatCell(QTableWidgetItem):
    def __init__(self, string, tableId, seat):
        super(TableSeatCell, self).__init__(string)

        self.tableId = tableId
        self.seat = seat

class TablesTable(QTableWidget):
    def __init__(self, server, logger, refreshButton, parent=None):
        super(TablesTable, self).__init__(parent)

        self.server = server
        self.logger = logger
        self.timer = QTimer()

        self.server.connected.connect(self.updating)
        self.timer.timeout.connect(self.updating)
        refreshButton.clicked.connect(self.updating)
        
        server.eventDispatcher.connect(EventType.SIT, self.handle_player_sat_down)
        server.eventDispatcher.connect(EventType.STAND, self.handle_player_stands)

    def startUpdating(self):
        self.logger.append("Start Updating")
        self.timer.start(5000)
        self.updating()

    def updating(self):
        self.logger.append("Updating Tables")
        try:
            tableList = self.server.getTables()
        except InvalidOperation as exc:
            self.logger.append("<b>Failed: %s</b>" % (str(exc)))
            return

        self.clear()
        self.setRowCount(len(tableList))
        self.setColumnCount(5)
        self.setHorizontalHeaderLabels(
                ["Table", "Seat 1", "Seat 2", "Seat 3", "Seat 4"])
        self.verticalHeader().hide()
        self.setAlternatingRowColors(True)
        self.setEditTriggers(QTableWidget.NoEditTriggers)
        self.setSelectionMode(QTableWidget.SingleSelection)
        self.setSelectionBehavior(QTableWidget.SelectItems)

        for row, table in enumerate(tableList):
            item = QTableWidgetItem(str(table.tableId))
            item.setTextAlignment(QtCore.Qt.AlignCenter)
            self.setItem(row, 0, item)

            for col, seat in enumerate(table.seats):
                if not seat.isOpen:
                    item = QTableWidgetItem(seat.name)
                    item.setFlags(QtCore.Qt.NoItemFlags)
                else:
                    item = TableSeatCell("", table.tableId, col)
                self.setItem(row, col + 1, item)

#        self.tables.resizeColumnsToContents()

    def stopUpdating(self):
        self.logger.append("Stop Updating")
        self.timer.stop()

    def handle_player_sat_down(self, name, table, seat):
        self.logger.append("LOBBY: User %s takes seat #%d at table #%d" % (name, seat, table))
        self.updating()

    def handle_player_stands(self, table, seat, name):
        self.logger.append("LOBBY: User %s stands from seat #%d at table #%d" % (name, seat, table))
        self.updating()

class LoginFrame(QFrame):
    def __init__(self, server, logger, parent=None):
        super(LoginFrame, self).__init__(parent)
        self.logger = logger
        self.server = server
        self.connected = False

        layout = QGridLayout()

        layout.addWidget(QLabel("Host: "), 0, 0)

        self.host = QLineEdit("localhost")
        layout.addWidget(self.host, 0, 1)

        layout.addWidget(QLabel("Name: "), 1, 0)
        self.name = QLineEdit()
        layout.addWidget(self.name, 1, 1)

        self.connectButton = QPushButton("Connect")
        buttonLayout = QDialogButtonBox(Qt.Horizontal)
        buttonLayout.addButton(self.connectButton, QDialogButtonBox.ActionRole)
        buttonLayout.setCenterButtons(True)

        layout.addWidget(buttonLayout, 2, 0, 1, 0)

        self.setLayout(layout)

        self.connectButton.clicked.connect(self.pressConnectButton)

        self.server.connected.connect(self.handleConnected)
        self.server.disconnected.connect(self.handleDisconnected)

    def _enable_connection_widgets(self, enabled):
        self.host.setEnabled(enabled)
        self.name.setEnabled(enabled)

    def handleConnected(self):
        self.logger.append("<b>Connected</b>")
        self.connected = True
        self.connectButton.setText("Disconnect")
        self._enable_connection_widgets(False)

    def handleDisconnected(self):
        self.logger.append("<b>Disconnected</b>")
        self.connected = False
        self.connectButton.setText("Connect")
        self._enable_connection_widgets(True)
        self.name.clear()

    def pressConnectButton(self):
        try:
            if self.connected:
                self.server.disconnectFromServer()
            else:
                host = unicode(self.host.text())
                name = unicode(self.name.text())
                self.server.connectToServer(host, name)
        except Exception as exc: # TODO: better exception
            self.logger.append("<b>Failed: %s</b>" % (str(exc)))


class MainForm(QMainWindow):

    def __init__(self, server, resource_path, parent=None):
        super(MainForm, self).__init__(parent)

        self.resource_path = resource_path
        self.server = server
        self.tables = []
        self.logger = QTextBrowser()
        self.login = LoginFrame(server, self.logger)

        line = QFrame()
        line.setFrameStyle(QFrame.HLine | QFrame.Sunken)

        tableRefreshButton = QPushButton("Refresh")
        self.tablesTable = TablesTable(server, self.logger, tableRefreshButton)

        tableLabel = QLabel("Tables:")
        tableLabel.setAlignment(QtCore.Qt.AlignCenter)

        tablesLayout = QVBoxLayout()
        tablesLayout.setContentsMargins(0, 0, 0, 0);
        tablesLayout.addStretch()
        tablesLayout.addWidget(tableLabel)
        tablesLayout.addWidget(tableRefreshButton)
        tablesLayout.addStretch()

        logLabel = QLabel("Log:")
        logLabel.setAlignment(QtCore.Qt.AlignCenter)

        bottomLayout = QGridLayout()
        bottomLayout.setContentsMargins(0, 0, 0, 0);
        bottomLayout.addLayout(tablesLayout, 0, 0)
        bottomLayout.addWidget(self.tablesTable, 0, 1)
        bottomLayout.addWidget(logLabel, 1, 0)
        bottomLayout.addWidget(self.logger, 1, 1)

        layout = QVBoxLayout()
        layout.addWidget(self.login)
        layout.addWidget(line)
        layout.addLayout(bottomLayout)

        main = QFrame()
        main.setLayout(layout)
        self.setCentralWidget(main)

        self.setWindowTitle("Tarabish")

        self.tablesTable.itemDoubleClicked.connect(self.handleSit)

    def handleSit(self, tableSeatCell):
        # Not a seat column
        if tableSeatCell.column() == 0:
            return
        
        self.logger.append("Joining table %d, seat %d" % (tableSeatCell.tableId,
            tableSeatCell.seat))

        table_id = tableSeatCell.tableId
        seat_num = tableSeatCell.seat

        try:
            table_view = self.server.sit(table_id, seat_num)
            table = Table(table_id, seat_num, table_view, self.server,
                    self.logger, self.resource_path)
            self.tables.append(table)
            table.show()
            self.tablesTable.updating()
        except InvalidOperation as exc:
            self.logger.append("<b>Failed: %s</b>" % (str(exc)))
